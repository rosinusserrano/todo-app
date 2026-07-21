// Sync configuration.
//
// The server is self-hosted, so the address and token are things the user types
// in from their own server's console. Both are stored device-locally and never
// synced.
//
// "Test" checks reachability before "Sync now" is worth trying, so a wrong
// address reports itself as a wrong address rather than as an auth failure.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../sync/sync_client.dart';
import '../theme.dart';

const kServerUrl = 'sync:server-url';
const kServerToken = 'sync:token';

Future<void> showSyncSettings(BuildContext context, AppState state) {
  return showDialog(
    context: context,
    builder: (_) => _SyncDialog(state: state),
  );
}

class _SyncDialog extends StatefulWidget {
  const _SyncDialog({required this.state});

  final AppState state;

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  final _url = TextEditingController();
  final _token = TextEditingController();

  String? _message;
  bool _ok = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = widget.state.store;
    _url.text = await store.setting(kServerUrl) ?? '';
    _token.text = await store.setting(kServerToken) ?? '';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  SyncClient? _client() {
    final base = SyncClient.parseBase(_url.text);
    if (base == null) {
      setState(() {
        _message = 'Enter an address like 192.168.2.184:8787';
        _ok = false;
      });
      return null;
    }
    return SyncClient(baseUrl: base.toString(), token: _token.text.trim());
  }

  Future<void> _save() async {
    final store = widget.state.store;
    final base = SyncClient.parseBase(_url.text);
    await store.setSetting(kServerUrl, base?.toString() ?? '');
    await store.setSetting(kServerToken, _token.text.trim());
  }

  Future<void> _test() async {
    final client = _client();
    if (client == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    final result = await client.checkReachable();
    client.dispose();
    if (!mounted) return;

    setState(() {
      _busy = false;
      _ok = result is SyncOk;
      _message = switch (result) {
        SyncOk() => 'Server reachable.',
        SyncFailed(:final message) => message,
      };
    });
  }

  Future<void> _syncNow() async {
    final client = _client();
    if (client == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    await _save();
    final result = await client.syncOnce(widget.state.store);
    client.dispose();
    if (!mounted) return;

    if (result is SyncOk) {
      // The lists on screen are now stale - the merge may have brought in
      // tasks from another device.
      await widget.state.refreshWorkspaces();
      await widget.state.refreshTasks();
      await widget.state.refreshThoughts();
    }
    if (!mounted) return;

    setState(() {
      _busy = false;
      _ok = result is SyncOk;
      _message = switch (result) {
        SyncOk(:final applied, :final pushed) =>
          'Synced. Sent $pushed, received $applied.',
        SyncFailed(:final message) => message,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: const Text('Sync', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Run `npm run server` on any machine, then enter the address '
              'and token it prints.',
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
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: _ok ? const Color(0xFF7EE3A1) : T.danger,
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _test,
          child: const Text('Test'),
        ),
        TextButton(
          onPressed: () async {
            await _save();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _busy ? null : _syncNow,
          child: const Text('Sync now'),
        ),
      ],
    );
  }
}
