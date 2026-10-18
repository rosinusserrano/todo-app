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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../startup.dart';
import '../sync/sync_client.dart';
import '../sync/sync_service.dart';
import '../sync/oidc_client.dart';
import '../theme.dart';
import 'push_settings.dart';
import 'sso_sign_in.dart';
import 'server_users_view.dart';
import 'dock.dart' show DockEdge;
import 'title_bar.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.sync,
    required this.accent,
    required this.onClose,
    this.zoom = 1.0,
    this.onZoom,
    this.startup,
    this.onOpenHistory,
    this.dockEdge = DockEdge.top,
    this.onDockEdge,
    this.archivedCount = 0,
    this.archive,
  });

  final SyncService sync;
  final Color accent;
  final VoidCallback onClose;

  /// The whole widget's size, 1.0 for as designed, and how to change it. A
  /// null [onZoom] hides the row.
  final double zoom;
  final ValueChanged<double>? onZoom;

  /// Absent on the platforms that have no such concept, which is what hides
  /// the whole section rather than showing a dead switch.
  final StartupSetting? startup;

  /// Opens this workspace's History. Non-null only on a phone, where the view
  /// bar's fourth place went to the thought pile and History moved here: it is
  /// looked back at now and then, which is what a settings visit is.
  final VoidCallback? onOpenHistory;

  /// Where the dock goes in a wide window, and how to change it. A narrow
  /// window keeps it at the bottom whatever this says. Null hides the row.
  final DockEdge dockEdge;
  final ValueChanged<DockEdge>? onDockEdge;

  /// How many projects are archived, and the page that shows them
  /// (archived_projects.dart). The row is drawn only while there is one.
  final int archivedCount;
  final Widget Function()? archive;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  // In a browser the server is wherever the page came from - the sync server
  // serves the web build itself - so a blank address starts as the page's own
  // origin and only the token is left to type. Elsewhere `Uri.base` is the
  // working directory, hence the check.
  late final _url = TextEditingController(
    text: widget.sync.baseUrl ?? (kIsWeb ? Uri.base.origin : ''),
  );
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

  /// The archived projects, shown in place the same way.
  bool _showArchive = false;

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
    SyncStatus.ok => T.ok,
    SyncStatus.error => T.warn,
    // A version mismatch is red for the same reason a bad token is: neither
    // recovers on its own. `describe()` is what says which of the two it is,
    // and it names the machine that has to change.
    SyncStatus.blocked || SyncStatus.outdated => T.danger,
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
            top: Radius.circular(T.radius),
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
                  : _showArchive && widget.archive != null
                  ? widget.archive!()
                  : _settingsBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s2, 2),
      child: Row(
        children: [
          if (_showUsers || _showArchive)
            InkWell(
              onTap: () => setState(() {
                _showUsers = false;
                _showArchive = false;
              }),
              borderRadius: BorderRadius.circular(T.radius),
              child: const Padding(
                padding: EdgeInsets.only(right: T.s2),
                child: Icon(Icons.arrow_back, size: 14, color: T.muted),
              ),
            ),
          Text(
            _showUsers
                ? 'People on this server'
                : _showArchive
                ? 'Archived projects'
                : 'Settings',
            style: const TextStyle(
              fontSize: T.fsLabel,
              fontWeight: T.wMedium,
              color: T.muted,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(T.radius),
            child: const Padding(
              padding: EdgeInsets.all(T.s2),
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
    style: const TextStyle(fontSize: T.fsBody),
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
        style: const TextStyle(fontSize: T.fsMeta, color: T.danger, height: 1.4),
      );
    }

    if (signedIn) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Signed in as ${widget.sync.identity?.label ?? 'this account'}.',
              style: const TextStyle(fontSize: T.fsLabel, color: T.muted),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              await widget.sync.signOut();
              if (mounted) setState(() {});
            },
            child: const Text('Sign out', style: TextStyle(fontSize: T.fsLabel)),
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
            style: TextStyle(fontSize: T.fsLabel),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Opens your browser. Your account is created the first time you '
          'sign in.',
          style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.35),
        ),
      ],
    );
  }

  Widget _archiveRow() {
    final n = widget.archivedCount;
    return InkWell(
      onTap: () => setState(() => _showArchive = true),
      borderRadius: BorderRadius.circular(T.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s2),
        child: Row(
          children: [
            const Icon(Icons.archive_outlined, size: 18, color: T.muted),
            const SizedBox(width: T.s2),
            const Expanded(
              child: Text(
                'Archived projects',
                style: TextStyle(fontSize: T.fsBody, color: T.text),
              ),
            ),
            Text(
              '$n',
              style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
            ),
            const SizedBox(width: T.s1),
            const Icon(Icons.chevron_right_rounded, size: 18, color: T.muted),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.radius),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: T.s2),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: T.muted),
            SizedBox(width: T.s2),
            Expanded(
              child: Text(
                'History',
                style: TextStyle(fontSize: T.fsBody, color: T.text),
              ),
            ),
            Text(
              'Completed tasks',
              style: TextStyle(fontSize: T.fsMeta, color: T.muted),
            ),
            SizedBox(width: T.s1),
            Icon(Icons.chevron_right_rounded, size: 18, color: T.muted),
          ],
        ),
      ),
    );
  }

  /// − 130% +, with a tap on the number for 100%. Steps rather than a
  /// slider, because the widget redraws at the new size under the finger and
  /// a slider would be dragged by a hand that just moved.
  Widget _zoomRow(ValueChanged<double> onZoom) {
    final steps = T.zoomSteps;
    final i = steps.indexOf(widget.zoom);
    Widget step(IconData icon, String tip, int by) {
      final j = i + by;
      final ok = i >= 0 && j >= 0 && j < steps.length;
      return IconButton(
        tooltip: tip,
        icon: Icon(icon, size: 18),
        color: T.text,
        disabledColor: T.muted.withValues(alpha: 0.4),
        onPressed: ok ? () => onZoom(steps[j]) : null,
      );
    }

    return Row(
      children: [
        const Icon(Icons.text_fields_rounded, size: 18, color: T.muted),
        const SizedBox(width: T.s2),
        const Expanded(
          child: Text(
            'Zoom',
            style: TextStyle(fontSize: T.fsBody, color: T.text),
          ),
        ),
        step(Icons.remove_rounded, 'Smaller', -1),
        Tooltip(
          message: 'Back to 100%',
          child: InkWell(
            onTap: widget.zoom == 1.0 ? null : () => onZoom(1.0),
            borderRadius: BorderRadius.circular(T.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: T.s1,
                vertical: T.s2,
              ),
              child: Text(
                '${(widget.zoom * 100).round()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: T.fsLabel, color: T.text),
              ),
            ),
          ),
        ),
        step(Icons.add_rounded, 'Larger', 1),
      ],
    );
  }

  /// Three touching blocks, one lit - the dock's own shape, so the choice
  /// looks like the thing it moves.
  Widget _dockRow(ValueChanged<DockEdge> onDockEdge) {
    Widget choice(DockEdge edge) {
      final on = widget.dockEdge == edge;
      final fill = on
          ? widget.accent
          : Color.lerp(T.bgSolid, T.text, 0.08)!;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: fill,
            child: InkWell(
              onTap: () => onDockEdge(edge),
              child: SizedBox(
                height: 36,
                child: Center(
                  child: Text(
                    edge.label,
                    style: TextStyle(
                      fontSize: T.fsLabel,
                      fontFamily: T.fontDisplay,
                      fontWeight: on ? T.wMedium : T.wNormal,
                      color: on ? T.inkOn(fill) : T.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.space_dashboard_outlined, size: 18, color: T.muted),
            SizedBox(width: T.s2),
            Expanded(
              child: Text(
                'Dock in a wide window',
                style: TextStyle(fontSize: T.fsBody, color: T.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: T.s2),
        Row(
          children: [
            for (final e in const [DockEdge.top, DockEdge.left, DockEdge.bottom])
              choice(e),
          ],
        ),
      ],
    );
  }

  Widget _settingsBody() {
    final sync = widget.sync;
    final config = _authConfig;

    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s3, T.s3),
      children: [
        if (widget.onOpenHistory != null) _historyRow(widget.onOpenHistory!),
        if (widget.archive != null && widget.archivedCount > 0) _archiveRow(),
        if (widget.onZoom != null) _zoomRow(widget.onZoom!),
        if (widget.onDockEdge != null) ...[
          const SizedBox(height: T.s2),
          _dockRow(widget.onDockEdge!),
        ],
        if (widget.onOpenHistory != null ||
            (widget.archive != null && widget.archivedCount > 0) ||
            widget.onZoom != null ||
            widget.onDockEdge != null)
          const SizedBox(height: T.s3),
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
        }, style: const TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4)),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _url,
                style: const TextStyle(fontSize: T.fsBody),
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
                style: const TextStyle(fontSize: T.fsLabel),
              ),
            ),
          ],
        ),
        if (_connectError != null) ...[
          const SizedBox(height: 8),
          Text(
            _connectError!,
            style: const TextStyle(
              fontSize: T.fsMeta,
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
                style: TextStyle(fontSize: T.fsMeta, color: _statusColor()),
              ),
            ),
          ],
        ),
        if (_testMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _testMessage!,
            style: TextStyle(
              fontSize: T.fsMeta,
              color: _testOk ? T.ok : T.danger,
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
          style: TextStyle(fontSize: T.fsMeta, color: T.muted),
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
                  style: TextStyle(fontSize: T.fsLabel),
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
            style: const TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
          ),
        ],

        // The browser build only: the native apps schedule their own.
        if (kIsWeb) ...[
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 10),
          PushSettings(sync: sync),
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
                  style: TextStyle(fontSize: T.fsLabel),
                ),
              ),
              Switch(value: _launchAtStartup, onChanged: _setStartup),
            ],
          ),
          const Text(
            'Opens the widget when you sign in. It also lives in the tray, '
            'so it can be hidden without being closed.',
            style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
          ),
        ],
      ],
    );
  }
}
