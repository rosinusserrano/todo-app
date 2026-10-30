// API tokens: credentials for scripts on other machines, made by the account
// that owns them.
//
// A token from here is an *inbox* token (server/users.js INBOX_SCOPE): it can
// send this account a notification, a thought or a todo, and read nothing -
// so a script's .env holding one can fill the pile but not see what is in
// it. How to call it is API.md at the repo root, which is public so that an
// agent working in some other project can be pointed at it; the dialog that
// shows a new token says where. Device tokens are not here: those are the
// admin's (People on this server), and revoking the one this app syncs with
// from a list like this is a lock-out.
//
// A page inside the settings sheet like ServerUsersView, for its reason (a
// route's barrier would cover the title bar), and like it every action ends
// by reloading from the server, which is the truth here.

import 'package:flutter/material.dart';

import '../sync/admin_client.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'token_dialogs.dart';

/// Where the requests are described. Public, so an agent can read it.
const kApiDocsUrl = 'https://github.com/rosinusserrano/todo-app/blob/main/API.md';

class ApiTokensView extends StatefulWidget {
  const ApiTokensView({super.key, required this.sync, required this.onBack});

  final SyncService sync;
  final VoidCallback onBack;

  @override
  State<ApiTokensView> createState() => _ApiTokensViewState();
}

class _ApiTokensViewState extends State<ApiTokensView> {
  List<ServerToken>? _tokens;
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

  Future<void> _load() async {
    final client = _client();
    try {
      final tokens = await client.apiTokens();
      if (mounted) {
        setState(() {
          _tokens = tokens;
          _error = null;
        });
      }
    } on AdminException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      client.dispose();
    }
  }

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

  Future<void> _add() async {
    final name = await promptTokenName(
      context,
      title: 'New API token',
      hint: 'What will use it?',
      help: 'One token per script or server, so revoking one stops only '
          'that one. It can send you notifications, thoughts and todos, and '
          'cannot read anything.',
    );
    if (name == null) return;

    final token = await _run((c) => c.addApiToken(name));
    if (token == null || !mounted) return;
    final url = widget.sync.baseUrl!;
    await showIssuedToken(
      context,
      token: token,
      subtitle: 'For $name',
      footer: 'Put it in the project\'s .env - "Copy .env lines" copies '
          'TODO_URL=$url and TODO_TOKEN with it. How to make the requests: '
          '$kApiDocsUrl',
      copyText: 'TODO_URL=$url\nTODO_TOKEN=$token\n',
      copyLabel: 'Copy .env lines',
    );
  }

  Future<void> _revoke(ServerToken token) async {
    final ok = await confirmDanger(
      context,
      title: 'Revoke "${token.label}"?',
      body: 'Whatever uses it gets "Invalid token" from its next request on. '
          'Nothing it already sent is removed.',
      danger: 'Revoke',
    );
    if (ok) await _run((c) => c.revokeApiToken(token));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens ?? const <ServerToken>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy || _tokens == null) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s3, T.s2),
            children: [
              const Text(
                'For scripts on other machines: with one of these, a POST to '
                'this server sends you a notification, adds a thought or adds '
                'a todo. A token cannot read anything.',
                style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
              ),
              const SizedBox(height: T.s1),
              const SelectableText(
                'How: $kApiDocsUrl',
                style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: T.fsMeta, color: T.danger)),
              ],
              const SizedBox(height: 12),
              if (_tokens != null && tokens.isEmpty)
                const Text(
                  'No tokens yet.',
                  style: TextStyle(fontSize: T.fsLabel, color: T.muted),
                ),
              for (final t in tokens) _tile(t),
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
                onPressed: _busy ? null : _add,
                child: const Text('New token'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(ServerToken t) {
    final kind = t.scope == 'notify' ? 'notifications only' : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.label, style: const TextStyle(fontSize: T.fsLabel, color: T.text)),
                Text(
                  [?kind, t.describe()].join(' · '),
                  style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Revoke',
            onPressed: _busy ? null : () => _revoke(t),
            icon: const Icon(Icons.block_rounded, size: 16, color: T.danger),
          ),
        ],
      ),
    );
  }
}
