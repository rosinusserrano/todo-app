// Settings: sync configuration, plus the handful of device-local preferences.
//
// The server is self-hosted, so the address and token come from the user's own
// server console. Both are stored device-locally and never synced.
//
// "Test" checks reachability without the token, so a wrong address reports
// itself as a wrong address rather than as an auth failure.

import 'package:flutter/material.dart';

import '../startup.dart';
import '../sync/sync_client.dart';
import '../sync/sync_service.dart';
import '../theme.dart';

Future<void> showSyncSettings(
  BuildContext context,
  SyncService sync, {
  StartupSetting? startup,
}) {
  return showDialog(
    context: context,
    builder: (_) => _SyncDialog(sync: sync, startup: startup),
  );
}

class _SyncDialog extends StatefulWidget {
  const _SyncDialog({required this.sync, this.startup});

  final SyncService sync;

  /// Absent on the platforms that have no such concept, which is what hides
  /// the whole section rather than showing a dead switch.
  final StartupSetting? startup;

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  late final _url = TextEditingController(text: widget.sync.baseUrl ?? '');
  late final _token = TextEditingController(text: widget.sync.token ?? '');

  String? _testMessage;
  bool _testOk = false;
  bool _busy = false;
  bool _launchAtStartup = false;

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_onSync);
    _loadStartup();
  }

  Future<void> _loadStartup() async {
    final startup = widget.startup;
    if (startup == null) return;
    final on = await startup.isEnabled();
    if (mounted) setState(() => _launchAtStartup = on);
  }

  /// Shows the state that actually took effect, not the one that was asked
  /// for - the Run key can be refused on a managed machine, and a switch that
  /// slid across anyway would be lying.
  Future<void> _setStartup(bool on) async {
    final startup = widget.startup;
    if (startup == null) return;
    setState(() => _launchAtStartup = on);
    final actual = await startup.setEnabled(on);
    if (mounted) setState(() => _launchAtStartup = actual);
  }

  @override
  void dispose() {
    widget.sync.removeListener(_onSync);
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _onSync() {
    if (mounted) setState(() {});
  }

  Future<void> _test() async {
    final base = SyncClient.parseBase(_url.text);
    if (base == null) {
      setState(() {
        _testOk = false;
        _testMessage = 'Enter an address like 192.168.2.184:8787';
      });
      return;
    }

    setState(() {
      _busy = true;
      _testMessage = null;
    });

    final client = SyncClient(baseUrl: base.toString(), token: _token.text.trim());
    final result = await client.checkReachable();
    client.dispose();
    if (!mounted) return;

    setState(() {
      _busy = false;
      _testOk = result is SyncOk;
      _testMessage = switch (result) {
        SyncOk() => 'Server reachable.',
        SyncFailed(:final message) => message,
      };
    });
  }

  Future<void> _saveAndSync() async {
    setState(() => _busy = true);
    await widget.sync.configure(_url.text, _token.text);
    await widget.sync.syncNow();
    if (mounted) setState(() => _busy = false);
  }

  Color _statusColor() => switch (widget.sync.status) {
        SyncStatus.ok => const Color(0xFF7EE3A1),
        SyncStatus.error => const Color(0xFFFFCF6C),
        SyncStatus.blocked => T.danger,
        _ => T.muted,
      };

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;

    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: const Text('Settings', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 330,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Run `npm run server` on any machine, then enter the address and '
              'token it prints. Everything stays on your own hardware.',
              style: TextStyle(fontSize: 11.5, color: T.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _url,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: '192.168.2.184:8787',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _token,
              style: const TextStyle(fontSize: 13),
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Token',
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _statusColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sync.describe(),
                    style: TextStyle(fontSize: 11.5, color: _statusColor()),
                  ),
                ),
              ],
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _testMessage!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: _testOk ? const Color(0xFF7EE3A1) : T.danger,
                ),
              ),
            ],
            if (_busy || sync.status == SyncStatus.syncing) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 6),
            const Text(
              'Syncs automatically every minute and shortly after each change.',
              style: TextStyle(fontSize: 10.5, color: T.muted),
            ),
            if (widget.startup != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0x14FFFFFF)),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Start with Windows',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Switch(
                    value: _launchAtStartup,
                    onChanged: _setStartup,
                  ),
                ],
              ),
              const Text(
                'Opens the widget when you sign in. It also lives in the tray, '
                'so it can be hidden without being closed.',
                style: TextStyle(fontSize: 10.5, color: T.muted, height: 1.4),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : _test, child: const Text('Test')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _busy ? null : _saveAndSync,
          child: const Text('Save & sync'),
        ),
      ],
    );
  }
}
