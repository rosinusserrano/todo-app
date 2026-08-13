// Background sync.
//
// The settings dialog could already push a manual sync; this makes it
// automatic, and gives the UI something honest to display. Three rules shape
// it:
//
//   - Never block the UI. Every local write lands in the local database first
//     and syncs afterwards, so the app is fully usable with the server off.
//   - Never overlap. Two concurrent syncs would push the same dirty rows twice
//     and race on the cursor.
//   - Never spin on a broken config. A wrong token is not going to fix itself,
//     so polling stops until the settings change.
//
// The offline story falls out of the first rule: a write goes into the local
// database, is flagged `dirty`, and stays there until a sync accepts it. With
// the server off, that is simply a sync that fails and gets retried - nothing
// is queued in memory, so it survives a restart, and `pending` is what the UI
// shows so the user can tell queued work from lost work.
//
// The one thing the poll cannot cover is a *suspended* app. On a phone the
// timer stops with the process, so a phone that spent the night asleep would
// otherwise wait a further minute after unlock before pushing. `resume()` is
// the app-lifecycle hook that closes that gap.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'change_stream.dart';
import 'local_store.dart';
import 'models.dart' show newId;
import 'oidc_client.dart';
import 'sync_client.dart';

enum SyncStatus {
  /// No server configured.
  off,

  /// Configured, nothing happening right now.
  idle,
  syncing,

  /// Last attempt succeeded.
  ok,

  /// Last attempt failed but may recover (server asleep, no network).
  error,

  /// Last attempt failed in a way the user has to fix (bad token/address).
  blocked,
}

const kServerUrl = 'sync:server-url';
const kServerToken = 'sync:token';

/// Which server and account this database's `dirty` flags are relative to.
///
/// `dirty` only ever meant "*a* server has accepted this row". That is enough
/// while there is one server for the life of an install, and silently wrong the
/// moment there is not: repoint the app at a rebuilt database or a different
/// account and every clean row is already-sent here and absent there, so it is
/// never pushed again. This is the fact that makes the difference noticeable -
/// when it stops matching, the flags mean nothing and everything is re-armed.
///
/// Device-local, like every other key here: it describes this copy of the
/// database, not the todo list.
const kServerFingerprint = 'sync:fingerprint';

/// This device's name for itself on the event stream, minted once and kept.
///
/// Device-local by definition, and not a credential: the server uses it only to
/// leave us out of the broadcast our own push caused.
const kDeviceId = 'sync:device-id';

/// The single sign-on session, when there is one. Device-local by nature - a
/// refresh token is this device's credential, and syncing it would hand every
/// other device the ability to mint access tokens as you.
const kOidcRefresh = 'sync:oidc-refresh';
const kOidcAccess = 'sync:oidc-access';
const kOidcExpires = 'sync:oidc-expires';
const kOidcClientId = 'sync:oidc-client-id';
const kOidcTokenEndpoint = 'sync:oidc-token-endpoint';

class SyncService extends ChangeNotifier {
  SyncService(this._store, {this.onChangesApplied});

  final LocalStore _store;

  /// Called after a sync that actually brought rows in, so the UI can reload.
  final Future<void> Function()? onChangesApplied;

  static const _interval = Duration(seconds: 60);
  static const _debounce = Duration(seconds: 2);

  /// Minimum gap between two resume-triggered syncs. See [resume].
  static const _resumeGap = Duration(seconds: 20);

  String? baseUrl;
  String? token;

  /// The signed-in SSO session, or null when this device uses a device token.
  ///
  /// When set it *supersedes* [token]: the access token it holds is short-lived
  /// and refreshed on demand, so the bearer is asked for per request rather
  /// than read from storage.
  OidcSession? oidcSession;

  bool get isSignedInWithSso => oidcSession != null;

  /// Which account this token belongs to, once a sync has succeeded and the
  /// server has been asked. Null on an older server, or before the first sync.
  ///
  /// Not persisted: it is the server's answer, not a device setting, and a
  /// remembered "you are an admin" would outlive the server saying so.
  ServerIdentity? identity;

  /// Whether to offer the user-management panel. The server enforces this for
  /// itself on every admin route - this only decides what is worth showing.
  bool get isAdmin => identity?.admin ?? false;

  SyncStatus status = SyncStatus.off;
  String? message;
  DateTime? lastSynced;

  /// Local rows not yet accepted by the server. Zero after a clean sync.
  int pending = 0;

  Timer? _periodic;
  Timer? _debounceTimer;
  bool _inFlight = false;

  /// The open connection the server pushes change hints down, when there is
  /// one. Null until the first sync succeeds: there is no point holding a
  /// stream open against an address or a token that has not been shown to work,
  /// and a failed sync already says so in a way the user can act on.
  ChangeStream? _stream;

  /// This device's id on that stream. Read once at [load].
  String? _deviceId;

  /// Whether changes made elsewhere arrive immediately rather than on the next
  /// poll. False is not a fault - it means the server predates the feature, or
  /// the stream is between attempts - and the poll covers it either way.
  bool get isLive => _stream?.connected ?? false;

  /// A local change arrived mid-sync. Its dirty rows were not in the payload
  /// that went out, so another pass is needed once this one lands.
  bool _dirtyAgain = false;

  bool get isConfigured =>
      (baseUrl?.isNotEmpty ?? false) &&
      ((token?.isNotEmpty ?? false) || oidcSession != null);

  /// The bearer for the next request.
  ///
  /// Returns null when an SSO session exists but could not be refreshed, which
  /// is a state the caller has to surface rather than retry: the refresh token
  /// is spent and only a fresh sign-in fixes it.
  Future<String?> _bearer() async {
    final session = oidcSession;
    if (session == null) return token;
    try {
      return await session.accessToken();
    } on OidcAuthException {
      return null;
    }
  }

  Future<void> load() async {
    baseUrl = await _store.setting(kServerUrl);
    token = await _store.setting(kServerToken);
    _deviceId = await _loadDeviceId();
    await _restoreSso();
    status = isConfigured ? SyncStatus.idle : SyncStatus.off;
    await refreshPending();
    notifyListeners();
    if (isConfigured) {
      _startPolling();
      unawaited(syncNow());
    }
  }

  /// Rebuild the SSO session from what was stored, if anything was.
  ///
  /// The provider's endpoints are stored with the tokens rather than rediscovered
  /// here, so a device that starts offline can still refresh the moment the
  /// network comes back - and so a sync server that is briefly down does not
  /// cost the session it is not involved in.
  Future<void> _restoreSso() async {
    final refresh = await _store.setting(kOidcRefresh);
    final tokenEndpoint = await _store.setting(kOidcTokenEndpoint);
    if (refresh == null || refresh.isEmpty || tokenEndpoint == null) return;

    final expires = DateTime.tryParse(await _store.setting(kOidcExpires) ?? '');
    adoptSso(
      AuthConfig(
        mode: 'oidc',
        clientId: await _store.setting(kOidcClientId),
        tokenEndpoint: tokenEndpoint,
        deviceEndpoint: null,
      ),
      OidcTokens(
        accessToken: await _store.setting(kOidcAccess) ?? '',
        refreshToken: refresh,
        // Absent or unparseable means "assume stale", which costs one refresh
        // and is the safe direction to be wrong in.
        expiresAt: expires ?? DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }

  /// Take a completed sign-in and start using it.
  void adoptSso(AuthConfig config, OidcTokens tokens) {
    oidcSession = OidcSession(
      client: OidcClient(config: config),
      tokens: tokens,
      save: (t) => _persistSso(config, t),
    );
  }

  Future<void> _persistSso(AuthConfig config, OidcTokens tokens) async {
    await _store.setSetting(kOidcAccess, tokens.accessToken);
    await _store.setSetting(kOidcRefresh, tokens.refreshToken ?? '');
    await _store.setSetting(kOidcExpires, tokens.expiresAt.toIso8601String());
    await _store.setSetting(kOidcClientId, config.clientId ?? '');
    await _store.setSetting(kOidcTokenEndpoint, config.tokenEndpoint ?? '');
  }

  /// Finish a sign-in: adopt the tokens, store them, and start syncing.
  Future<void> signedIn(AuthConfig config, OidcTokens tokens) async {
    adoptSso(config, tokens);
    await _persistSso(config, tokens);

    // A pasted device token and an SSO session are alternatives, not layers.
    // Leaving the old one behind would mean signing out silently fell back to
    // an account the user thought they had stopped using.
    token = '';
    await _store.setSetting(kServerToken, '');

    identity = null;
    status = isConfigured ? SyncStatus.idle : SyncStatus.off;
    message = null;
    notifyListeners();

    _stopPolling();
    // A different credential is a different connection; the open one is
    // authenticated as whoever we just stopped being.
    unawaited(_stopStream());
    if (isConfigured) {
      _startPolling();
      unawaited(syncNow());
    }
  }

  /// Forget the SSO session. Local data is untouched - this is a credential
  /// being dropped, not an account being left.
  Future<void> signOut() async {
    oidcSession = null;
    for (final key in [
      kOidcAccess,
      kOidcRefresh,
      kOidcExpires,
      kOidcClientId,
      kOidcTokenEndpoint,
    ]) {
      await _store.setSetting(key, '');
    }
    identity = null;
    status = isConfigured ? SyncStatus.idle : SyncStatus.off;
    message = null;
    _stopPolling();
    unawaited(_stopStream());
    notifyListeners();
  }

  /// Re-count the rows waiting to go out.
  ///
  /// Cheap (an indexed COUNT per table) and only ever called around a sync or
  /// a lifecycle change, not per keystroke.
  Future<void> refreshPending() async {
    final count = await _store.pendingCount();
    if (count == pending) return;
    pending = count;
    notifyListeners();
  }

  /// Check the database's `dirty` flags still mean something on this server,
  /// and re-arm every row if they do not. Returns whether it re-armed.
  ///
  /// Runs once per configuration, right after [identity] is answered, because
  /// that is the one moment both halves of the fingerprint are known. Three
  /// cases reach the re-arm, and all three want the same thing:
  ///
  ///   - **No fingerprint stored.** The database predates this check, so its
  ///     flags were never tied to anything and there is no way to tell an
  ///     in-sync copy from one that has been quietly diverging since the last
  ///     server rebuild. Prove it once rather than assume.
  ///   - **A different account.** Same address, another token: those rows have
  ///     never been to this account at all.
  ///   - **A different address.** A move, or a restore onto a new host.
  ///
  /// Proving it is cheap by design - see [LocalStore.markAllDirty] for why a
  /// re-arm that turns out to be unnecessary writes nothing on the server.
  Future<bool> _reconcileFingerprint() async {
    final id = identity;
    // An older server has no /api/me, and an unreachable one answers nothing.
    // Neither is evidence of a change, and re-arming on "don't know" would do
    // it on every launch against such a server.
    if (id == null) return false;

    final current = '$baseUrl|${id.user}';
    final stored = await _store.setting(kServerFingerprint);
    await _store.setSetting(kServerFingerprint, current);
    if (stored == current) return false;

    await _store.markAllDirty();
    await refreshPending();
    notifyListeners();
    return true;
  }

  /// This device's id on the event stream, minting one the first time.
  Future<String> _loadDeviceId() async {
    final stored = await _store.setting(kDeviceId);
    if (stored != null && stored.isNotEmpty) return stored;
    final minted = newId();
    await _store.setSetting(kDeviceId, minted);
    return minted;
  }

  /// Open the change stream, if it should be open and is not.
  ///
  /// Called after a sync that worked, which is the cheapest possible proof that
  /// the address and the credential are both good - so this never becomes a
  /// second thing to debug when sync itself is misconfigured.
  void _ensureStream() {
    if (!isConfigured || _stream != null) return;

    _stream = ChangeStream(
      baseUrl: baseUrl!,
      deviceId: _deviceId ?? '',
      bearer: _bearer,
      // Not scheduleSync: the debounce exists to coalesce *our own* rapid
      // edits, and a hint means the rows are already on the server. Waiting
      // two more seconds would be latency added to the exact thing this is
      // here to remove. syncNow coalesces on its own - a hint arriving mid-sync
      // sets _dirtyAgain rather than starting a second one.
      onHint: () => unawaited(syncNow()),
      onStateChanged: notifyListeners,
    )..start();
  }

  Future<void> _stopStream() async {
    final stream = _stream;
    _stream = null;
    await stream?.stop();
  }

  /// The app came back to the foreground.
  ///
  /// A suspended process runs no timers, so this pushes immediately and
  /// restarts the poll, which is what makes a phone that was offline all night
  /// sync on unlock rather than a minute later.
  ///
  /// Desktop reports the same lifecycle change on every *focus* change, and an
  /// always-on-top widget is focused constantly, so this is rate-limited:
  /// without the gap, alt-tabbing back would sync each time, and restarting
  /// the poll on each one would keep pushing the periodic sync out of reach.
  void resume() {
    unawaited(refreshPending());
    if (!isConfigured || status == SyncStatus.blocked) return;

    final since = lastSynced;
    if (since != null && DateTime.now().difference(since) < _resumeGap) return;

    // A process that was suspended holds a socket the other end has long since
    // dropped, and it cannot know that: no packet arrives to say so, and the
    // watchdog that would eventually notice was frozen too. Waking is the one
    // moment we know for certain the connection is suspect, so drop it and let
    // the sync below earn a fresh one.
    unawaited(_stopStream());

    _startPolling();
    unawaited(syncNow());
  }

  Future<void> configure(String url, String tokenValue) async {
    final parsed = SyncClient.parseBase(url);
    baseUrl = parsed?.toString() ?? '';
    token = tokenValue.trim();
    await _store.setSetting(kServerUrl, baseUrl!);
    await _store.setSetting(kServerToken, token!);

    // Pasting a device token replaces an SSO session rather than sitting
    // behind it - see signedIn() for the same rule in the other direction.
    if (token!.isNotEmpty && oidcSession != null) {
      await signOut();
    }

    // A different token is a different account, so who we are is now unknown
    // rather than what it was a moment ago.
    identity = null;
    status = isConfigured ? SyncStatus.idle : SyncStatus.off;
    message = null;
    notifyListeners();

    // Settings changed, so a previously blocked config is worth retrying.
    _stopPolling();
    // Including the stream: it may be open against the address we just left.
    unawaited(_stopStream());
    if (isConfigured) _startPolling();
  }

  void _startPolling() {
    _periodic?.cancel();
    _periodic = Timer.periodic(_interval, (_) {
      // A config the user must fix will not fix itself on a timer.
      if (status == SyncStatus.blocked) return;
      unawaited(syncNow());
    });
  }

  void _stopPolling() {
    _periodic?.cancel();
    _periodic = null;
  }

  /// Called after a local mutation. Debounced, so typing several tasks in a row
  /// produces one sync rather than one per keystroke-completed entry.
  void scheduleSync() {
    if (!isConfigured) return;
    // Count now rather than after the attempt: with the server off, that is
    // the difference between the queue showing up immediately and only after
    // the request has finished timing out.
    unawaited(refreshPending());
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    if (!isConfigured) return;
    if (_inFlight) {
      _dirtyAgain = true;
      return;
    }

    _inFlight = true;
    status = SyncStatus.syncing;
    notifyListeners();

    final bearer = await _bearer();
    if (bearer == null || bearer.isEmpty) {
      // Blocked rather than error: no amount of retrying mints a new token, and
      // the status is what tells the settings sheet to offer signing in again.
      status = SyncStatus.blocked;
      message = 'Signed out. Sign in again to resume syncing.';
      _inFlight = false;
      notifyListeners();
      return;
    }

    final client =
        SyncClient(baseUrl: baseUrl!, token: bearer, deviceId: _deviceId);
    SyncResult result;
    try {
      result = await client.syncOnce(_store);
      // Only once per configuration, and only on the back of a sync that
      // already worked - so this is never the reason a sync is slow, and never
      // a request made against a server that just refused us.
      if (result is SyncOk && identity == null) {
        identity = await client.whoAmI();
        // Same pass, for the same reason: this is the one moment we know both
        // which server answered and which account it called us.
        if (await _reconcileFingerprint()) _dirtyAgain = true;
      }
      // Rows the re-arm just flagged were not in the payload that went out.
      if (result is SyncOk && result.rearmed) _dirtyAgain = true;
    } finally {
      client.dispose();
      _inFlight = false;
    }

    switch (result) {
      case SyncOk(:final applied):
        status = SyncStatus.ok;
        message = null;
        lastSynced = DateTime.now();
        if (applied > 0) await onChangesApplied?.call();
        // The address and the credential have just been shown to work, which
        // is the only precondition the stream has.
        _ensureStream();
      case SyncFailed(message: final failure, transient: final canRetry):
        // A transient failure keeps polling; a blocked one stops until the
        // settings change, since a wrong token will not fix itself.
        status = canRetry ? SyncStatus.error : SyncStatus.blocked;
        message = failure;
        // A credential the user has to fix is not something to hold a
        // connection open through. A server that is merely down is: the stream
        // has its own backoff, and reconnecting is how it notices the server
        // came back.
        if (!canRetry) unawaited(_stopStream());
    }
    await refreshPending();
    notifyListeners();

    if (_dirtyAgain) {
      _dirtyAgain = false;
      unawaited(syncNow());
    }
  }

  /// Human-readable state for the settings dialog.
  ///
  /// When the server is unreachable the failure alone reads like data loss, so
  /// it is followed by the queue depth: the work is on disk and will go out.
  String describe() {
    if (!isConfigured) return 'No server configured.';
    final queued = pending == 0
        ? ''
        : ' $pending change${pending == 1 ? '' : 's'} waiting.';
    return switch (status) {
      SyncStatus.off => 'No server configured.',
      SyncStatus.idle => 'Waiting for first sync.$queued',
      SyncStatus.syncing => 'Syncing…',
      // "Live" is worth saying out loud: it is the difference between a change
      // from the phone appearing now and appearing within the minute, and
      // there is otherwise nothing on screen that would ever show it.
      SyncStatus.ok => lastSynced == null
          ? 'Synced.'
          : 'Last synced ${_ago(lastSynced!)}.${isLive ? ' Live.' : ''}',
      SyncStatus.error => '${message ?? 'Sync failed.'}$queued',
      SyncStatus.blocked =>
        '${message ?? 'Check the address and token.'}$queued',
    };
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 10) return 'just now';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  @override
  void dispose() {
    _stopPolling();
    unawaited(_stopStream());
    _debounceTimer?.cancel();
    super.dispose();
  }
}
