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
import '../sync/oidc_client.dart';
import '../theme.dart';
import 'sso_sign_in.dart';
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

  /// How the configured server wants to authenticate, once it has been asked.
  /// Null until then, which shows the token field - the right default, because
  /// that is what every server that does not answer means.
  AuthConfig? _authConfig;

  /// A Connect in flight, and why the last one failed. Both drive the button
  /// and the line under it; neither is worth persisting.
  bool _checking = false;
  String? _connectError;

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

    final client = SyncClient(
      baseUrl: base.toString(),
      token: _token.text.trim(),
    );
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
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 30,
              offset: Offset(0, -10),
            ),
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

  /// Ask the server how it wants to be logged in to.
  ///
  /// Only after the address is entered, and never blocking: a server that does
  /// not answer just leaves the token field on screen, which is what an older
  /// server means anyway.
  Future<void> _checkAuthMode() async {
    final base = SyncClient.parseBase(_url.text);
    if (base == null) {
      setState(() {
        _authConfig = null;
        _connectError =
            'Enter an address like todo.example.com or '
            '192.168.2.184:8787';
      });
      return;
    }

    setState(() {
      _checking = true;
      _connectError = null;
    });

    // Reachability first, and separately, so a wrong address reports itself as
    // a wrong address. AuthConfig.discover deliberately never throws - it
    // reports 'token' for anything it cannot read, which for an older server is
    // the right answer and for an unreachable one is a misleading one.
    final client = SyncClient(baseUrl: base.toString(), token: '');
    final reachable = await client.checkReachable();
    client.dispose();
    if (!mounted) return;

    if (reachable is SyncFailed) {
      setState(() {
        _checking = false;
        _authConfig = null;
        _connectError = reachable.message;
      });
      return;
    }

    final config = await AuthConfig.discover(base.toString());
    if (!mounted) return;
    setState(() {
      _checking = false;
      _authConfig = config;
      // The server has SSO but its provider is not answering. Saying so beats
      // showing a Sign in button that cannot work.
      _connectError = config.isOidc && !config.usable
          ? 'This server uses single sign-on, but its provider is not '
                'responding. Try again in a moment.'
          : null;
    });

    // A server that wants a token, with one already saved, is ready to go.
    if (!config.isOidc && _token.text.trim().isNotEmpty) await _saveAndSync();
  }

  Future<void> _signIn() async {
    final config = _authConfig;
    if (config == null || !config.usable) return;

    final tokens = await showSsoSignIn(context, config);
    if (tokens == null || !mounted) return;

    // The address has to be saved before the session is, or the sync that
    // starts on the back of signing in has nowhere to go.
    await widget.sync.configure(_url.text, '');
    await widget.sync.signedIn(config, tokens);
    if (!mounted) return;
    setState(() => _token.text = '');
  }

  Widget _tokenField() => TextField(
    controller: _token,
    style: const TextStyle(fontSize: 13),
    obscureText: true,
    decoration: const InputDecoration(labelText: 'Token', isDense: true),
  );

  Widget _ssoBlock() {
    final config = _authConfig!;
    final signedIn = widget.sync.isSignedInWithSso;

    if (config.error != null) {
      // SSO is configured but the provider is not answering. Falling back to
      // the token field here would send the user looking for a credential they
      // are not supposed to need.
      return Text(
        'The server uses single sign-on but cannot reach its provider right '
        'now. Try again in a moment.',
        style: const TextStyle(fontSize: 11.5, color: T.danger, height: 1.4),
      );
    }

    if (signedIn) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Signed in as ${widget.sync.identity?.label ?? 'this account'}.',
              style: const TextStyle(fontSize: 12, color: T.muted),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              await widget.sync.signOut();
              if (mounted) setState(() {});
            },
            child: const Text('Sign out', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      );
    }

    // Full width and on its own, because at this point it is the only thing to
    // do on this screen. The old layout put it at the end of a row next to a
    // token field, which read as the alternative to the token rather than as
    // the way in.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: config.usable ? _signIn : null,
          icon: const Icon(Icons.login_rounded, size: 16),
          label: const Text(
            'Sign in with your account',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Opens your browser. Your account is created the first time you '
          'sign in.',
          style: TextStyle(fontSize: 10.5, color: T.muted, height: 1.35),
        ),
      ],
    );
  }

  Widget _settingsBody() {
    final sync = widget.sync;
    final config = _authConfig;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      children: [
        Text(switch (config?.mode) {
          'oidc' =>
            'This server signs you in with your own account. '
                'Nobody has to issue you anything.',
          'token' =>
            'Enter the token the server printed. Everything stays '
                'on your own hardware.',
          // Before Connect has been pressed there is nothing to say about a
          // server we have not spoken to yet, so this describes the step in
          // front of them rather than guessing at the one after it.
          _ =>
            'Sync keeps your devices in step through a server you run. '
                'Enter its address to see how it wants you to sign in.',
        }, style: const TextStyle(fontSize: 11.5, color: T.muted, height: 1.4)),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _url,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Server address',
                  hintText: 'todo.example.com',
                  isDense: true,
                ),
                // Editing invalidates what the last address told us: leaving
                // the old answer on screen would offer SSO for a server that
                // may not have it, or a token field for one that does.
                onChanged: (_) {
                  if (_authConfig != null) setState(() => _authConfig = null);
                },
                onSubmitted: (_) => _checkAuthMode(),
              ),
            ),
            const SizedBox(width: 8),
            // An explicit step, not a blur handler. Asking the server how to
            // log in is a network call with a visible result, so it gets a
            // button you can press again when it fails.
            FilledButton(
              onPressed: _checking ? null : _checkAuthMode,
              child: Text(
                _checking ? '…' : 'Connect',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
        if (_connectError != null) ...[
          const SizedBox(height: 8),
          Text(
            _connectError!,
            style: const TextStyle(
              fontSize: 11.5,
              color: T.danger,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (config == null)
          const SizedBox.shrink()
        else if (config.isOidc)
          _ssoBlock()
        else
          _tokenField(),
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
            TextButton(
              onPressed: _busy ? null : _test,
              child: const Text('Test'),
            ),
            const Spacer(),
            // In SSO mode the credential is the session, not anything in a
            // field, so this only ever saves the address - and saying "Save &
            // sync" there would imply it had stored something it had not.
            FilledButton(
              onPressed: _busy ? null : _saveAndSync,
              child: Text(
                (_authConfig?.isOidc ?? false) ? 'Save address' : 'Save & sync',
              ),
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
                child: Text(
                  'People on this server',
                  style: TextStyle(fontSize: 12.5),
                ),
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
                child: Text(
                  'Start with Windows',
                  style: TextStyle(fontSize: 12.5),
                ),
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
