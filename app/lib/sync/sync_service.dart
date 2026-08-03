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

import 'local_store.dart';
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

  /// A local change arrived mid-sync. Its dirty rows were not in the payload
  /// that went out, so another pass is needed once this one lands.
  bool _dirtyAgain = false;

  bool get isConfigured => (baseUrl?.isNotEmpty ?? false) && (token?.isNotEmpty ?? false);

  Future<void> load() async {
    baseUrl = await _store.setting(kServerUrl);
    token = await _store.setting(kServerToken);
    status = isConfigured ? SyncStatus.idle : SyncStatus.off;
    await refreshPending();
    notifyListeners();
    if (isConfigured) {
      _startPolling();
      unawaited(syncNow());
    }
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

    _startPolling();
    unawaited(syncNow());
  }

  Future<void> configure(String url, String tokenValue) async {
    final parsed = SyncClient.parseBase(url);
    baseUrl = parsed?.toString() ?? '';
    token = tokenValue.trim();
    await _store.setSetting(kServerUrl, baseUrl!);
    await _store.setSetting(kServerToken, token!);

    // A different token is a different account, so who we are is now unknown
    // rather than what it was a moment ago.
    identity = null;
    status = isConfigured ? SyncStatus.idle : SyncStatus.off;
    message = null;
    notifyListeners();

    // Settings changed, so a previously blocked config is worth retrying.
    _stopPolling();
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

    final client = SyncClient(baseUrl: baseUrl!, token: token!);
    SyncResult result;
    try {
      result = await client.syncOnce(_store);
      // Only once per configuration, and only on the back of a sync that
      // already worked - so this is never the reason a sync is slow, and never
      // a request made against a server that just refused us.
      if (result is SyncOk && identity == null) {
        identity = await client.whoAmI();
      }
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
      case SyncFailed(message: final failure, transient: final canRetry):
        // A transient failure keeps polling; a blocked one stops until the
        // settings change, since a wrong token will not fix itself.
        status = canRetry ? SyncStatus.error : SyncStatus.blocked;
        message = failure;
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
      SyncStatus.ok => lastSynced == null
          ? 'Synced.'
          : 'Last synced ${_ago(lastSynced!)}.',
      SyncStatus.error => '${message ?? 'Sync failed.'}$queued',
      SyncStatus.blocked => '${message ?? 'Check the address and token.'}$queued',
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
    _debounceTimer?.cancel();
    super.dispose();
  }
}
