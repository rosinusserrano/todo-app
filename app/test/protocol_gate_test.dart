// What an incompatible server costs: nothing, and it costs it loudly.
//
// The unit half of this lives in protocol_test.dart - who is behind, and what
// an absent field means. This half is the behaviour that matters: when the two
// ends do not speak the same wire, **no rows move**. A check that reported a
// mismatch and synced anyway would fire at exactly the moment a row gets
// written wrong, which is the moment it exists to prevent.
//
// The server here is a real HttpServer on loopback, like server_swap_test's, so
// what is under test is the actual sequence of requests the app makes - in
// particular that the health probe happens *before* /api/sync rather than after
// it, which is the whole difference between a gate and a report.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/protocol.dart';
import 'package:todo_widget/sync/sync_service.dart';

class _FakeServer {
  _FakeServer(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakeServer> start() async =>
      _FakeServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  /// What `/api/health` reports, or null to answer nothing about the wire -
  /// which is what every server deployed before the handshake does.
  ServerProtocol? protocol = ServerProtocol.legacy;

  /// Every path asked for, in order. The order is the assertion.
  final List<String> hits = [];

  int rowsPushed = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  bool get synced => hits.contains('/api/sync');

  Future<void> _handle(HttpRequest req) async {
    hits.add(req.uri.path);
    final res = req.response..headers.contentType = ContentType.json;

    if (req.uri.path == '/api/health') {
      final p = protocol;
      res.write(jsonEncode({
        'ok': true,
        'service': 'todo-widget-sync',
        'version': 1,
        if (p != null) 'protocol': p.speaks,
        if (p != null) 'minClient': p.minClient,
      }));
      await res.close();
      return;
    }
    if (req.uri.path == '/api/me') {
      res.write(jsonEncode({'user': 'local', 'label': 'local', 'admin': false}));
      await res.close();
      return;
    }
    if (req.uri.path == '/api/events') {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }

    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
    final changes = (body['changes'] as Map?) ?? {};
    for (final rows in changes.values) {
      rowsPushed += (rows as List).length;
    }
    res.write(jsonEncode({'cursor': 1, 'changes': {}}));
    await res.close();
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// A first successful sync queues a second one through `_dirtyAgain` (the
  /// fingerprint re-arm), and the UI never waits on sync - so `syncNow` returns
  /// with another one already in flight. Give it room before asserting on the
  /// status, exactly as server_swap_test does.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  Future<LocalStore> storeWithWork() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    await state.addTask('something worth syncing');
    expect(await store.pendingCount(), greaterThan(0));
    return store;
  }

  test('a server that will not accept this app gets no rows', () async {
    final server = await _FakeServer.start();
    server.protocol = const ServerProtocol(
      speaks: kSyncProtocol + 1,
      minClient: kSyncProtocol + 1,
    );
    final store = await storeWithWork();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    await sync.syncNow();

    expect(server.synced, isFalse, reason: 'nothing may be pushed');
    expect(server.rowsPushed, 0);
    expect(sync.status, SyncStatus.outdated);
    expect(sync.compatibility, Compatibility.appTooOld);
    expect(sync.describe(), contains('too old for this server'));

    // The work is still queued, not lost or quietly marked as sent. That is
    // what makes this airplane mode with a reason attached: fix the mismatch
    // and everything goes up on the next cycle.
    expect(await store.pendingCount(), greaterThan(0));

    sync.dispose();
    await server.stop();
  });

  test('the probe happens before any rows are offered', () async {
    // A gate, not a report. If /api/sync came first the rows would already
    // have been written by the time the mismatch was noticed.
    final server = await _FakeServer.start();
    server.protocol = const ServerProtocol(
      speaks: kSyncProtocol + 1,
      minClient: kSyncProtocol + 1,
    );
    final store = await storeWithWork();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    await sync.syncNow();

    expect(server.hits.first, '/api/health');

    sync.dispose();
    await server.stop();
  });

  test('a compatible server syncs as it always did', () async {
    final server = await _FakeServer.start();
    final store = await storeWithWork();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    await sync.syncNow();
    await settle();

    expect(server.synced, isTrue);
    expect(server.rowsPushed, greaterThan(0));
    expect(sync.status, SyncStatus.ok);
    expect(sync.compatibility, Compatibility.ok);

    sync.dispose();
    await server.stop();
  });

  test('a server that has never heard of the handshake syncs too', () async {
    // The case that makes this safe to switch on at all: every server already
    // deployed answers /api/health without these fields, and must keep working
    // exactly as it did.
    final server = await _FakeServer.start();
    server.protocol = null;
    final store = await storeWithWork();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    await sync.syncNow();
    await settle();

    expect(server.synced, isTrue);
    expect(sync.status, SyncStatus.ok);

    sync.dispose();
    await server.stop();
  });

  test('once agreed, the probe is not repeated on every sync', () async {
    final server = await _FakeServer.start();
    final store = await storeWithWork();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    await sync.syncNow();
    await settle();
    await sync.syncNow();
    await settle();

    expect(
      server.hits.where((p) => p == '/api/health').length,
      1,
      reason: 'the handshake is per configuration, not per sync',
    );

    sync.dispose();
    await server.stop();
  });

  test('a new address is a new handshake', () async {
    // A server that agreed with us says nothing about the next one, so
    // configure() has to forget.
    final first = await _FakeServer.start();
    final second = await _FakeServer.start();
    second.protocol = const ServerProtocol(
      speaks: kSyncProtocol + 1,
      minClient: kSyncProtocol + 1,
    );
    final store = await storeWithWork();
    final sync = SyncService(store);

    await sync.configure(first.url, 'a-token');
    await sync.syncNow();
    await settle();
    expect(sync.status, SyncStatus.ok);

    await sync.configure(second.url, 'a-token');
    await sync.syncNow();
    expect(sync.status, SyncStatus.outdated);
    expect(second.synced, isFalse);

    sync.dispose();
    await first.stop();
    await second.stop();
  });
}
