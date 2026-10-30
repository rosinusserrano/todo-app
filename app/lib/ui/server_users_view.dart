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
// server stores only a hash, so `showIssuedToken` (token_dialogs.dart) is the
// single moment that string exists anywhere - it gets its own dialog, a copy
// button, and says so plainly. Everything else on this screen is recoverable;
// that is not.

import 'package:flutter/material.dart';

import '../sync/admin_client.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'token_dialogs.dart';

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
    final name = await promptTokenName(
      context,
      title: 'New account',
      hint: 'Their name',
      help: 'They get their own tasks, notes and calendar on this server. '
          'Nothing is shared with yours.',
    );
    if (name == null) return;

    final issued = await _run((c) => c.addUser(name));
    if (issued != null && mounted) {
      await showIssuedToken(
        context,
        token: issued.token,
        subtitle: 'Give this to $name',
        footer: 'They enter it in Settings, with the same server address.',
      );
    }
  }

  Future<void> _addToken(ServerUser user) async {
    final name = await promptTokenName(
      context,
      title: 'Another token for ${user.label}',
      hint: 'Which device?',
      help: 'One token per device means losing a phone costs that phone only. '
          'Sharing one token across devices works too.',
      initial: 'device',
    );
    if (name == null) return;

    final issued = await _run((c) => c.addToken(user, name));
    if (issued != null && mounted) {
      await showIssuedToken(
        context,
        token: issued.token,
        subtitle: 'For ${user.label}',
        footer: 'They enter it in Settings, with the same server address.',
      );
    }
  }

  Future<void> _revoke(ServerUser user, ServerToken token) async {
    final ok = await confirmDanger(
      context,
      title: 'Revoke "${token.label}"?',
      body: 'That device stops syncing on its next attempt. It keeps the copy '
          'it already has. ${user.label} can be given a new token at any time.',
      danger: 'Revoke',
    );
    if (ok) await _run((c) => c.revokeToken(token));
  }

  Future<void> _deleteUser(ServerUser user) async {
    final ok = await confirmDanger(
      context,
      title: 'Delete ${user.label}?',
      body: 'Removes the account and everything in it from this server: tasks, '
          'notes, journal and calendar. Their devices keep their local copies, '
          'but will stop syncing. This cannot be undone.',
      danger: 'Delete',
    );
    if (ok) await _run((c) => c.deleteUser(user));
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
            padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s3, T.s2),
            children: [
              const Text(
                'Each account has its own tasks, notes, journal and calendar. '
                'Nothing is shared between them.',
                style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: T.fsMeta, color: T.danger)),
              ],
              const SizedBox(height: 12),
              for (final user in _users ?? const <ServerUser>[]) _userTile(user, me),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s2, 0, T.s2, T.s2),
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
      padding: const EdgeInsets.only(bottom: T.s3),
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
                      style: const TextStyle(fontSize: T.fsBody, color: T.text),
                    ),
                    if (isMe)
                      const TextSpan(
                        text: '  you',
                        style: TextStyle(fontSize: T.fsMeta, color: T.accent),
                      ),
                    if (user.admin)
                      const TextSpan(
                        text: '  admin',
                        style: TextStyle(fontSize: T.fsMeta, color: T.muted),
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
                    child: Text('Add a device', style: TextStyle(fontSize: T.fsLabel)),
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
                        fontSize: T.fsLabel,
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
              padding: const EdgeInsets.only(left: T.s1, top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${token.label} · ${token.describe()}',
                      style: TextStyle(
                        fontSize: T.fsMeta,
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
              padding: EdgeInsets.only(left: T.s1, top: 2),
              child: Text(
                'No working token — add a device to let them back in.',
                style: TextStyle(fontSize: T.fsMeta, color: T.danger, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }
}
