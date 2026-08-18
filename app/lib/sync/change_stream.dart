// The live half of sync: an open connection the server pushes hints down.
//
// Polling every 60 seconds is what made this app usable offline, and it is also
// why a task ticked off on the phone sat there for up to a minute before the
// desktop noticed. This closes that gap without touching the thing that works:
// the server says "your account moved" and the client runs *the same sync it
// would have run anyway*, immediately instead of on the next tick.
//
// So the contract is deliberately tiny, and everything here follows from it:
//
//   - **No rows come down this pipe.** A hint is a nudge, not data. There is
//     therefore exactly one way rows enter the database (`SyncClient.syncOnce`)
//     and one place conflicts are resolved, which is what makes this safe to
//     add to a merge protocol that already works.
//   - **A dropped hint costs latency, nothing else.** The poll is still
//     running underneath. That is why there is no acknowledgement, no replay
//     and no per-connection cursor: a missed hint is caught within the minute,
//     so none of that machinery would ever earn its keep.
//   - **It gives up on its own.** A server too old to have the route, or a
//     credential it rejects, must not become a client that reconnects forever.
//
// See server/events.js for the other end.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Reads a `text/event-stream` and calls back on every hint.
class ChangeStream {
  ChangeStream({
    required this.baseUrl,
    required this.deviceId,
    required this.bearer,
    required this.onHint,
    this.onStateChanged,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final String baseUrl;

  /// What this device calls itself, so the server can leave it out of the
  /// broadcast its own push caused. Not a credential - see server/events.js.
  final String deviceId;

  /// The bearer for the next connect. Asked for per attempt rather than held,
  /// so a reconnect after an SSO refresh presents the new access token.
  final Future<String?> Function() bearer;

  /// "Something changed on the server." Carries nothing, on purpose.
  final VoidCallback onHint;

  final http.Client Function() _clientFactory;

  /// Called when [connected] or [supported] changes, so the settings sheet can
  /// say whether this is live without polling it.
  final VoidCallback? onStateChanged;

  /// Backoff between reconnection attempts. A self-hosted server is restarted,
  /// rebooted and moved; reconnecting has to be patient rather than turn a
  /// server that is down into a client that hammers it.
  static const _minBackoff = Duration(seconds: 2);
  static const _maxBackoff = Duration(seconds: 60);

  /// How long silence is allowed to last before the connection is presumed
  /// dead. The server sends a keep-alive comment every 25s, so anything past
  /// twice that is a socket that was reclaimed without either end being told -
  /// the usual outcome of a NAT timeout or a laptop suspending.
  static const _silence = Duration(seconds: 70);

  http.Client? _client;
  StreamSubscription<String>? _lines;
  Timer? _retry;
  Timer? _watchdog;
  Duration _backoff = _minBackoff;
  bool _running = false;

  bool _connected = false;

  /// A stream is open and has been greeted by the server.
  bool get connected => _connected;

  bool _supported = true;

  /// False once the server has said it does not have this route. Instant sync
  /// is then simply off for this configuration, and the poll is the whole story
  /// again - which is exactly how the app behaved before this file existed.
  bool get supported => _supported;

  void start() {
    if (_running) return;
    _running = true;
    _supported = true;
    _backoff = _minBackoff;
    unawaited(_connect());
  }

  /// Stop for good. Safe to call when never started, and safe to call twice.
  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _retry = null;
    _watchdog?.cancel();
    _watchdog = null;
    await _lines?.cancel();
    _lines = null;
    _client?.close();
    _client = null;
    // Set directly rather than through _setConnected: this teardown is the
    // caller's own doing, so there is nobody to inform - and telling them
    // anyway means firing a callback into an owner that may be half way
    // through disposing, which is where this ran into
    // "a ChangeNotifier was used after being disposed".
    _connected = false;
  }

  Future<void> _connect() async {
    if (!_running) return;

    final token = await bearer();
    if (token == null || token.isEmpty) {
      // No credential to present. Whatever is wrong, reconnecting cannot fix
      // it, and syncNow is the path that reports it to the user.
      _running = false;
      return;
    }

    final client = _clientFactory();
    _client = client;

    try {
      final request = http.Request('GET', Uri.parse('$baseUrl/api/events'))
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'text/event-stream'
        // No compression: a gzip stream buffers, and a buffered hint is a hint
        // that arrives with the next one.
        ..headers['Accept-Encoding'] = 'identity'
        ..headers['X-Device-Id'] = deviceId
        ..persistentConnection = true;

      final response = await client.send(request);

      // [stop] may have run while that was in the air. Closing the client does
      // not cancel a request already sent, so without this the teardown is
      // undone from underneath: _setConnected(true) fires onStateChanged into
      // an owner that may be half way through dispose - the "ChangeNotifier
      // used after being disposed" that stop() bends over backwards to avoid -
      // and the listener attached below outlives the _lines that stop() has
      // already cancelled, leaving a live stream to a server we have finished
      // with quietly calling syncNow.
      if (!_running) {
        client.close();
        return;
      }

      if (response.statusCode == 404 || response.statusCode == 501) {
        // An older server. Not an error, just a server without the feature.
        _supported = false;
        _running = false;
        _setConnected(false);
        onStateChanged?.call();
        client.close();
        return;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        _running = false;
        _setConnected(false);
        client.close();
        return;
      }
      if (response.statusCode != 200) {
        _scheduleRetry();
        return;
      }

      // Connected. Reset the backoff here rather than on the first hint - a
      // server that is up but quiet is a healthy one.
      _backoff = _minBackoff;
      _setConnected(true);
      _pet();

      var event = '';
      _lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          _pet();
          if (line.startsWith(':')) return; // keep-alive comment
          if (line.startsWith('event: ')) {
            event = line.substring(7).trim();
            return;
          }
          if (line.startsWith('data: ')) {
            // The payload is not read on purpose. It carries a cursor, but
            // acting on it would mean trusting a number that arrived outside a
            // transaction; the sync it triggers computes its own. The hint is
            // the whole message.
            if (event == 'changed') onHint();
            return;
          }
          // A blank line ends an event; anything else is a field we do not use.
          if (line.isEmpty) event = '';
        },
        onError: (_) => _scheduleRetry(),
        onDone: _scheduleRetry,
        cancelOnError: true,
      );
    } catch (_) {
      // Server down, no route to host, DNS not resolving yet after a wake -
      // all of them mean the same thing here: try again later.
      _scheduleRetry();
    }
  }

  /// Restart the silence watchdog. Named for what it is: proof of life.
  void _pet() {
    _watchdog?.cancel();
    _watchdog = Timer(_silence, () {
      // Nothing has arrived, not even a heartbeat. The socket is open as far as
      // this end knows, which is exactly the state a reconnect exists for.
      _scheduleRetry();
    });
  }

  void _scheduleRetry() {
    if (!_running || _retry != null) return;

    _watchdog?.cancel();
    _watchdog = null;
    unawaited(_lines?.cancel());
    _lines = null;
    _client?.close();
    _client = null;
    _setConnected(false);

    _retry = Timer(_backoff, () {
      _retry = null;
      unawaited(_connect());
    });
    final next = _backoff * 2;
    _backoff = next > _maxBackoff ? _maxBackoff : next;
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onStateChanged?.call();
  }
}
