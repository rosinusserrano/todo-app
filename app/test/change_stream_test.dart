// The client end of instant sync.
//
// What is worth pinning here is not "a hint arrives" - it is the discipline
// around it. A change stream is a long-lived connection to a self-hosted server
// that gets restarted, suspended with the laptop and upgraded underneath the
// app, so the failure modes are all about what happens when it *stops* working:
// an older server must turn the feature off rather than produce a client that
// reconnects forever, and a dropped connection must come back on its own.
//
// The server here is a real HttpServer writing real `text/event-stream` bytes,
// because the parsing is half of what could be wrong.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/sync/change_stream.dart';

/// An SSE server the test drives by hand.
class _EventServer {
  _EventServer(this._server, {this.status = 200}) {
    _server.listen((req) async {
      seenDeviceIds.add(req.headers.value('x-device-id'));
      seenAuth.add(req.headers.value('authorization'));
      connections++;

      if (status != 200) {
        req.response.statusCode = status;
        await req.response.close();
        return;
      }

      req.response
        ..statusCode = 200
        ..headers.set('Content-Type', 'text/event-stream')
        // Dart buffers a response until it is closed unless told otherwise,
        // which for a stream that never closes means nothing ever arrives.
        ..bufferOutput = false;
      _open.add(req.response);
      _write(req.response, 'ready', {'ok': true});
    });
  }

  static Future<_EventServer> start({int status = 200}) async => _EventServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        status: status,
      );

  final HttpServer _server;
  final int status;
  final _open = <HttpResponse>[];

  /// How many times a client has asked for the stream. Reconnections included -
  /// that is the point of recording it.
  int connections = 0;
  final seenDeviceIds = <String?>[];
  final seenAuth = <String?>[];

  String get url => 'http://127.0.0.1:${_server.port}';

  void send(int cursor) {
    for (final res in _open) {
      _write(res, 'changed', {'cursor': cursor});
    }
  }

  /// Drop every open stream without answering, the way a restarted server does.
  Future<void> dropAll() async {
    for (final res in [..._open]) {
      await res.close();
    }
    _open.clear();
  }

  void _write(HttpResponse res, String event, Object data) {
    res.write('event: $event\ndata: ${jsonEncode(data)}\n\n');
  }

  Future<void> stop() async {
    await dropAll();
    await _server.close(force: true);
  }
}

void main() {
  /// Long enough for a round trip on loopback, short enough not to pad the run.
  Future<void> tick([int ms = 250]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  ChangeStream streamFor(
    _EventServer server, {
    required void Function() onHint,
    String token = 'a-token',
  }) =>
      ChangeStream(
        baseUrl: server.url,
        deviceId: 'this-device',
        bearer: () async => token,
        onHint: onHint,
      );

  test('a change event is a hint; the greeting is not', () async {
    final server = await _EventServer.start();
    var hints = 0;
    final stream = streamFor(server, onHint: () => hints++)..start();

    await tick();
    expect(stream.connected, isTrue);
    expect(hints, 0, reason: 'the ready line only proves the pipe works');

    server.send(12);
    await tick();
    expect(hints, 1);

    server.send(13);
    server.send(14);
    await tick();
    expect(hints, 3, reason: 'each change is its own nudge');

    await stream.stop();
    await server.stop();
  });

  test('the connection identifies the device and presents the token', () async {
    final server = await _EventServer.start();
    final stream = streamFor(server, onHint: () {})..start();
    await tick();

    // The device id is what keeps a push from coming back to its own author.
    expect(server.seenDeviceIds.single, 'this-device');
    expect(server.seenAuth.single, 'Bearer a-token');

    await stream.stop();
    await server.stop();
  });

  test('a server without the route turns the feature off for good', () async {
    // The whole point: an older server is a server without instant sync, not a
    // client that retries a 404 every two seconds until the app is closed.
    final server = await _EventServer.start(status: 404);
    final stream = streamFor(server, onHint: () {})..start();

    await tick();
    expect(stream.supported, isFalse);
    expect(stream.connected, isFalse);

    await tick(2500);
    expect(server.connections, 1, reason: 'it must not have tried again');

    await stream.stop();
    await server.stop();
  });

  test('a rejected token stops the stream rather than retrying', () async {
    final server = await _EventServer.start(status: 401);
    final stream = streamFor(server, onHint: () {})..start();

    await tick();
    await tick(2500);
    expect(server.connections, 1);
    expect(stream.connected, isFalse);
    // Unlike a 404 this is not "the server cannot do it", so the feature stays
    // supported - reconfiguring is what restarts it.
    expect(stream.supported, isTrue);

    await stream.stop();
    await server.stop();
  });

  test('a dropped connection comes back', () async {
    final server = await _EventServer.start();
    var hints = 0;
    final stream = streamFor(server, onHint: () => hints++)..start();

    await tick();
    expect(server.connections, 1);

    // A restarted server, a proxy timing out, a phone leaving a tunnel.
    await server.dropAll();
    await tick(2600); // past the two-second first backoff

    expect(server.connections, greaterThan(1));
    expect(stream.connected, isTrue);

    // And it is a working connection, not just an open one.
    server.send(1);
    await tick();
    expect(hints, 1);

    await stream.stop();
    await server.stop();
  });

  test('stopping is final, and safe to repeat', () async {
    final server = await _EventServer.start();
    var hints = 0;
    final stream = streamFor(server, onHint: () => hints++)..start();
    await tick();

    await stream.stop();
    await stream.stop();
    expect(stream.connected, isFalse);

    final after = server.connections;
    server.send(1);
    await tick(2500);
    expect(hints, 0, reason: 'a stopped stream hints at nothing');
    expect(server.connections, after, reason: 'and does not reconnect');

    await server.stop();
  });

  test('stopping mid-connect does not land a connection afterwards', () async {
    // stop() closes the client, but a request already sent is allowed to
    // finish - so the response can arrive after the teardown. Landing it would
    // fire onStateChanged into an owner that may be disposing (the crash stop()
    // is written to avoid) and attach a listener stop() has no way to cancel,
    // leaving a live stream to a server we are done with.
    final server = await _EventServer.start();
    var states = 0;
    final stream = ChangeStream(
      baseUrl: server.url,
      deviceId: 'this-device',
      bearer: () async => 'a-token',
      onHint: () {},
      onStateChanged: () => states++,
    );

    stream.start();
    // No `await tick()`: stop while the connect is still in the air, which is
    // what saving new sync settings or closing the app does.
    await stream.stop();
    states = 0;

    await tick(600);
    expect(stream.connected, isFalse, reason: 'the late response must not land');
    expect(states, 0, reason: 'nothing may be reported after the teardown');

    await server.stop();
  });

  test('no credential means no connection attempt', () async {
    final server = await _EventServer.start();
    final stream = ChangeStream(
      baseUrl: server.url,
      deviceId: 'this-device',
      // What a spent SSO refresh token looks like from here.
      bearer: () async => null,
      onHint: () {},
    )..start();

    await tick();
    expect(server.connections, 0);
    expect(stream.connected, isFalse);

    await stream.stop();
    await server.stop();
  });
}
