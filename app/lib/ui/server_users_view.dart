// Managing who else is on your sync server, from inside the app.
//
// Only an admin sees this - the account holding the token the server printed on
// its own console is one, and it can promote others. Everything here is also a
// command in `npm run token`; this exists because handing someone an account
// should not require walking to the machine the server runs on.
//
// A page inside the settings sheet rather than a dialog of its own: a modal
// route's barrier would cover the title bar and take the window's drag handle
// with it (see settings_sheet.dart), and a 340px window has no room to stack a
// panel on a panel. The small prompts below *are* dialogs - they are transient
// and genuinely modal, and one of them must be hard to dismiss by accident.
//
// The one thing the UI has to get right is that **a token is shown once**. The
// server stores only a hash, so `_showToken` is the single moment that string
// exists anywhere - it gets its own dialog, a copy button, and says so plainly.
// Everything else on this screen is recoverable; that is not.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/admin_client.dart';
import '../sync/sync_service.dart';
import '../theme.dart';

class ServerUsersView extends StatefulWidget {
  const ServerUsersView({super.key, required this.sync, required this.onBack});

  final SyncService sync;
  final VoidCallback onBack;

  @override
  State<ServerUsersView> createState() => _ServerUsersViewState();
}

class _ServerUsersViewState extends State<ServerUsersView> {
  List<ServerUser>? _users;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AdminClient _client() => AdminClient(
        baseUrl: widget.sync.baseUrl!,
        token: widget.sync.token!,
      );

  /// Every action ends by reloading rather than patching the list in place: the
  /// server is the truth here, and a second admin on another device may have
  /// changed it while this panel sat open.
  Future<void> _load() async {
    final client = _client();
    try {
      final users = await client.users();
      if (mounted) {
        setState(() {
          _users = users;
          _error = null;
        });
      }
    } on AdminException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      client.dispose();
    }
  }

  /// Runs an action, shows whatever it complained about, and reloads.
  Future<R?> _run<R>(Future<R> Function(AdminClient) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = _client();
    R? result;
    try {
      result = await action(client);
    } on AdminException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      client.dispose();
    }
    await _load();
    if (mounted) setState(() => _busy = false);
    return result;
  }

  Future<void> _addUser() async {
    final name = await _promptName(
      title: 'New account',
      hint: 'Their name',
      help: 'They get their own tasks, notes and calendar on this server. '
          'Nothing is shared with yours.',
    );
    if (name == null) return;

    final issued = await _run((c) => c.addUser(name));
    if (issued != null && mounted) {
      await _showToken(issued, 'Give this to $name');
    }
  }

  Future<void> _addToken(ServerUser user) async {
    final name = await _promptName(
      title: 'Another token for ${user.label}',
      hint: 'Which device?',
      help: 'One token per device means losing a phone costs that phone only. '
          'Sharing one token across devices works too.',
      initial: 'device',
    );
    if (name == null) return;

    final issued = await _run((c) => c.addToken(user, name));
    if (issued != null && mounted) {
      await _showToken(issued, 'For ${user.label}');
    }
  }

  Future<void> _revoke(ServerUser user, ServerToken token) async {
    final ok = await _confirm(
      title: 'Revoke "${token.label}"?',
      body: 'That device stops syncing on its next attempt. It keeps the copy '
          'it already has. ${user.label} can be given a new token at any time.',
      danger: 'Revoke',
    );
    if (ok) await _run((c) => c.revokeToken(token));
  }

  Future<void> _deleteUser(ServerUser user) async {
    final ok = await _confirm(
      title: 'Delete ${user.label}?',
      body: 'Removes the account and everything in it from this server: tasks, '
          'notes, journal and calendar. Their devices keep their local copies, '
          'but will stop syncing. This cannot be undone.',
      danger: 'Delete',
    );
    if (ok) await _run((c) => c.deleteUser(user));
  }

  // --------------------------------------------------------------- sub-dialogs

  Future<String?> _promptName({
    required String title,
    required String hint,
    required String help,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(help,
                  style: const TextStyle(fontSize: 11.5, color: T.muted, height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 60,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  counterText: '',
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    return (name == null || name.isEmpty) ? null : name;
  }

  /// The one and only appearance of a token. Deliberately hard to dismiss by
  /// accident - no barrier dismiss - because closing it loses the string.
  Future<void> _showToken(IssuedToken issued, String subtitle) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: const Text('Token', style: TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: const TextStyle(fontSize: 11.5, color: T.muted)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: T.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  issued.token,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontFamily: 'Consolas',
                    fontFamilyFallback: ['Menlo', 'monospace'],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'The server keeps only a hash of this, so it cannot be shown '
                'again. If it is lost, issue another and revoke this one.',
                style: TextStyle(fontSize: 10.5, color: T.muted, height: 1.4),
              ),
              const SizedBox(height: 8),
              const Text(
                'They enter it in Settings, with the same server address.',
                style: TextStyle(fontSize: 10.5, color: T.muted, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: issued.token));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copy & close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String danger,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 300,
          child: Text(body,
              style: const TextStyle(fontSize: 11.5, color: T.muted, height: 1.4)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: T.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(danger),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final me = widget.sync.identity?.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy || _users == null) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            children: [
              const Text(
                'Each account has its own tasks, notes, journal and calendar. '
                'Nothing is shared between them.',
                style: TextStyle(fontSize: 11.5, color: T.muted, height: 1.4),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 11.5, color: T.danger)),
              ],
              const SizedBox(height: 12),
              for (final user in _users ?? const <ServerUser>[]) _userTile(user, me),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              TextButton(onPressed: widget.onBack, child: const Text('Back')),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _addUser,
                child: const Text('Add person'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _userTile(ServerUser user, String? me) {
    final isMe = user.id == me;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: user.label,
                      style: const TextStyle(fontSize: 13, color: T.text),
                    ),
                    if (isMe)
                      const TextSpan(
                        text: '  you',
                        style: TextStyle(fontSize: 10.5, color: T.accent),
                      ),
                    if (user.admin)
                      const TextSpan(
                        text: '  admin',
                        style: TextStyle(fontSize: 10.5, color: T.muted),
                      ),
                  ]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_busy,
                tooltip: 'Manage ${user.label}',
                color: T.bgSolid,
                icon: const Icon(Icons.more_horiz, size: 16, color: T.muted),
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'token') _addToken(user);
                  if (value == 'delete') _deleteUser(user);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'token',
                    height: 36,
                    child: Text('Add a device', style: TextStyle(fontSize: 12.5)),
                  ),
                  // The server refuses both of these anyway; greying them out
                  // is so the refusal is not the first time anyone hears of it.
                  PopupMenuItem(
                    value: 'delete',
                    height: 36,
                    enabled: !isMe && !user.admin,
                    child: Text(
                      isMe
                          ? 'Delete (not yourself)'
                          : user.admin
                              ? 'Delete (drop admin first)'
                              : 'Delete account…',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: (isMe || user.admin) ? T.muted : T.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          for (final token in user.tokens)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${token.label} · ${token.describe()}',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        color: token.revoked ? T.muted.withValues(alpha: 0.5) : T.muted,
                        decoration: token.revoked ? TextDecoration.lineThrough : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!token.revoked)
                    IconButton(
                      onPressed: _busy ? null : () => _revoke(user, token),
                      icon: const Icon(Icons.close, size: 13),
                      color: T.muted,
                      tooltip: 'Revoke this token',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 22),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          if (user.activeTokens == 0)
            const Padding(
              padding: EdgeInsets.only(left: 4, top: 2),
              child: Text(
                'No working token — add a device to let them back in.',
                style: TextStyle(fontSize: 10.5, color: T.danger, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }
}
