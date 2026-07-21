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

  String? baseUrl;
  String? token;

  SyncStatus status = SyncStatus.off;
  String? message;
  DateTime? lastSynced;

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
    notifyListeners();
    if (isConfigured) {
      _startPolling();
      unawaited(syncNow());
    }
  }

  Future<void> configure(String url, String tokenValue) async {
    final parsed = SyncClient.parseBase(url);
    baseUrl = parsed?.toString() ?? '';
    token = tokenValue.trim();
    await _store.setSetting(kServerUrl, baseUrl!);
    await _store.setSetting(kServerToken, token!);

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
    notifyListeners();

    if (_dirtyAgain) {
      _dirtyAgain = false;
      unawaited(syncNow());
    }
  }

  /// Human-readable state for the settings dialog.
  String describe() {
    if (!isConfigured) return 'No server configured.';
    return switch (status) {
      SyncStatus.off => 'No server configured.',
      SyncStatus.idle => 'Waiting for first sync.',
      SyncStatus.syncing => 'Syncing…',
      SyncStatus.ok => lastSynced == null
          ? 'Synced.'
          : 'Last synced ${_ago(lastSynced!)}.',
      SyncStatus.error => message ?? 'Sync failed.',
      SyncStatus.blocked => message ?? 'Check the address and token.',
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
