// Settings: sync configuration, server user management, and the handful of
// device-local preferences.
//
// The server is self-hosted, so the address and token come from the user's own
// server console. Both are stored device-locally and never synced.
//
// "Test" checks reachability without the token, so a wrong address reports
// itself as a wrong address rather than as an auth failure.
//
// A **sheet in the shell's Stack, not a route dialog**, for the same reason
// SoundSheet is one: a modal route's barrier covers the whole window including
// the title bar, and the title bar is the drag handle — so an open settings
// dialog made the window impossible to move. This stops below TitleBar.height
// and leaves the bar on top, where it stays draggable and closable.
//
// The body scrolls. The widget is 480px tall by default and freely resizable,
// and this is the longest thing in the app; a Column that merely overflows gets
// squeezed into an unusable smear at small heights.

import 'package:flutter/material.dart';

import '../startup.dart';
import '../sync/sync_client.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'server_users_view.dart';
import 'title_bar.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.sync,
    required this.accent,
    required this.onClose,
    this.startup,
  });

  final SyncService sync;
  final Color accent;
  final VoidCallback onClose;

  /// Absent on the platforms that have no such concept, which is what hides
  /// the whole section rather than showing a dead switch.
  final StartupSetting? startup;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final _url = TextEditingController(text: widget.sync.baseUrl ?? '');
  late final _token = TextEditingController(text: widget.sync.token ?? '');

  String? _testMessage;
  bool _testOk = false;
  bool _busy = false;
  bool _launchAtStartup = false;

  /// The user-management page, shown in place of the settings body rather than
  /// as a dialog on top of it — a second modal route would put the barrier back
  /// over the title bar, and a 340px window has no room to stack panels anyway.
  bool _showUsers = false;

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
    final ws = widget.accent;

    return Positioned(
      top: TitleBar.height,
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Color.lerp(T.bgSolid, ws, 0.14),
          border: Border(top: BorderSide(color: ws.withValues(alpha: 0.35))),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(12),
            bottom: Radius.circular(T.radius),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, -10)),
          ],
        ),
        child: Column(
          children: [
            _head(),
            Expanded(
              child: _showUsers
                  ? ServerUsersView(
                      sync: widget.sync,
                      onBack: () => setState(() => _showUsers = false),
                    )
                  : _settingsBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 2),
      child: Row(
        children: [
          if (_showUsers)
            InkWell(
              onTap: () => setState(() => _showUsers = false),
              borderRadius: BorderRadius.circular(7),
              child: const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.arrow_back, size: 14, color: T.muted),
              ),
            ),
          Text(
            _showUsers ? 'People on this server' : 'Settings',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: T.muted,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(7),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 15, color: T.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsBody() {
    final sync = widget.sync;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
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
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton(onPressed: _busy ? null : _test, child: const Text('Test')),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _saveAndSync,
              child: const Text('Save & sync'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Syncs automatically every minute and shortly after each change.',
          style: TextStyle(fontSize: 10.5, color: T.muted),
        ),

        // Only for the account the server calls an admin, and only once a sync
        // has actually answered - a button that opens onto a 403 is worse than
        // no button. The server checks again on every route it serves.
        if (sync.isAdmin) ...[
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('People on this server',
                    style: TextStyle(fontSize: 12.5)),
              ),
              TextButton(
                onPressed: () => setState(() => _showUsers = true),
                child: const Text('Manage'),
              ),
            ],
          ),
          Text(
            'You are an admin of this server. Give someone their own account '
            'and token — signed in as ${sync.identity?.label ?? 'you'}.',
            style: const TextStyle(fontSize: 10.5, color: T.muted, height: 1.4),
          ),
        ],

        if (widget.startup != null) ...[
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('Start with Windows', style: TextStyle(fontSize: 12.5)),
              ),
              Switch(value: _launchAtStartup, onChanged: _setStartup),
            ],
          ),
          const Text(
            'Opens the widget when you sign in. It also lives in the tray, '
            'so it can be hidden without being closed.',
            style: TextStyle(fontSize: 10.5, color: T.muted, height: 1.4),
          ),
        ],
      ],
    );
  }
}
