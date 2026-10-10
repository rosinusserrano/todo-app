// Notifications in the browser build: the settings row that turns Web Push on
// for this device. See web_push.dart (the browser half) and server/push.js
// (who sends them).
//
// Only drawn on the web. The native apps schedule their own notifications and
// need nothing switched on here.
//
// The key is fetched when the row appears, not when Turn on is tapped: the
// browser only shows its permission prompt while the tap is being handled,
// and a network round trip first would spend that.

import 'package:flutter/material.dart';

import '../sync/push_client.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import '../web_push.dart';

class PushSettings extends StatefulWidget {
  const PushSettings({super.key, required this.sync});

  final SyncService sync;

  @override
  State<PushSettings> createState() => _PushSettingsState();
}

class _PushSettingsState extends State<PushSettings> {
  /// What the browser says, or null while asking.
  String? _state;
  String? _key;
  String? _message;
  bool _messageOk = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<PushClient?> _client() async {
    final sync = widget.sync;
    if (!sync.isConfigured) return null;
    final bearer = await sync.bearer();
    if (bearer == null || bearer.isEmpty) return null;
    return PushClient(baseUrl: sync.baseUrl!, token: bearer);
  }

  Future<void> _load() async {
    final state = await WebPush.state();
    if (!mounted) return;
    setState(() => _state = state);
    final client = await _client();
    if (client == null) return;
    try {
      if (state == 'off') {
        _key = await client.publicKey();
      } else if (state == 'on') {
        // Re-hand the subscription over. Idempotent, and it heals the cases
        // where the server forgot it: a rebuilt database, another account.
        final sub = await WebPush.current();
        if (sub != null) await client.register(sub);
      }
    } on PushException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      client.dispose();
    }
  }

  void _say(String message, {bool ok = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageOk = ok;
    });
  }

  /// Synchronous up to `WebPush.enable` on purpose - see the file header.
  void _turnOn() {
    final key = _key;
    if (key == null) {
      _say('Could not get the server\'s push key. Check the connection above.');
      return;
    }
    final asked = WebPush.enable(key);
    setState(() {
      _busy = true;
      _message = null;
    });
    _finishTurnOn(asked);
  }

  Future<void> _finishTurnOn(Future<String?> asked) async {
    PushClient? client;
    try {
      final sub = await asked;
      if (sub == null) {
        _say('Notifications were not allowed.');
        return;
      }
      client = await _client();
      if (client == null) {
        _say('Connect to your server above first.');
        return;
      }
      await client.register(sub);
      _say('On. Reminders will arrive on this device.', ok: true);
    } on PushException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('The browser refused: $e');
    } finally {
      client?.dispose();
      final state = await WebPush.state();
      if (mounted) {
        setState(() {
          _state = state;
          _busy = false;
        });
      }
    }
  }

  Future<void> _turnOff() async {
    setState(() => _busy = true);
    PushClient? client;
    try {
      final endpoint = await WebPush.disable();
      client = await _client();
      if (endpoint != null && client != null) await client.unregister(endpoint);
      _key ??= await client?.publicKey();
      _say('Off for this device.');
    } on PushException catch (e) {
      _say(e.message);
    } finally {
      client?.dispose();
      final state = await WebPush.state();
      if (mounted) {
        setState(() {
          _state = state;
          _busy = false;
        });
      }
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    PushClient? client;
    try {
      final sub = await WebPush.current();
      client = await _client();
      if (sub == null || client == null) {
        _say('Not subscribed on this device.');
        return;
      }
      // The endpoint is all the server needs to find it; register first in
      // case it had forgotten this browser.
      await client.register(sub);
      final endpoint = RegExp(r'"endpoint":"([^"]+)"').firstMatch(sub)?.group(1);
      if (endpoint == null) throw PushException('The browser sent no endpoint.');
      await client.test(endpoint);
      _say('Sent. It should appear in a few seconds.', ok: true);
    } on PushException catch (e) {
      _say(e.message);
    } finally {
      client?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final configured = widget.sync.isConfigured;

    final explain = switch (state) {
      null => '',
      'install' =>
        'On iPhone, notifications need the app on the Home Screen: tap Share, '
            'then Add to Home Screen, and open it from there.',
      'unsupported' => 'This browser cannot show notifications.',
      'denied' =>
        'Notifications are blocked for this app. Allow them in the system '
            'settings, then come back here.',
      'on' => 'On for this device. Task reminders and calendar alerts arrive '
          'even while the app is closed.',
      _ when !configured =>
        'Connect to your server above first: it is what sends them.',
      _ => 'Get task reminders and calendar alerts on this device, even while '
          'the app is closed.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Notifications', style: TextStyle(fontSize: T.fsLabel)),
            ),
            if (state == 'off' && configured)
              FilledButton(
                onPressed: _busy ? null : _turnOn,
                child: const Text('Turn on'),
              ),
            if (state == 'on') ...[
              TextButton(
                onPressed: _busy ? null : _test,
                child: const Text('Test'),
              ),
              TextButton(
                onPressed: _busy ? null : _turnOff,
                child: const Text('Turn off'),
              ),
            ],
          ],
        ),
        if (explain.isNotEmpty)
          Text(
            explain,
            style: const TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
          ),
        if (_message != null) ...[
          const SizedBox(height: T.s1),
          Text(
            _message!,
            style: TextStyle(
              fontSize: T.fsMeta,
              color: _messageOk ? T.ok : T.warn,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
