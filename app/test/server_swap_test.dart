// Pointing the app at a different sync database than the one that cleared its
// `dirty` flags.
//
// This is the failure these tests exist for, and it happened: a server was
// rebuilt, every local row was already clean from the *old* database, so the
// client pushed nothing and the new server ended up holding only the rows that
// happened to be edited afterwards. Both sides were internally consistent and
// permanently different, and nothing on either side noticed - a second device
// set up against the new server pulled the fragment and looked, correctly, like
// sync was working.
//
// Two independent signals catch it, and they are tested separately because
// either one can fire without the other: the cursor going backwards (the same
// account on a rebuilt database) and the fingerprint changing (a different
// address or a different account).
//
// The server here is a real HttpServer on loopback rather than a mocked client,
// so what is under test is the actual request the app makes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/sync_service.dart';

/// A sync server that holds nothing and answers whatever the test tells it to.
///
/// It records what was pushed, which is the only assertion that really matters
/// here: the point of a re-arm is that the rows actually go out.
class _FakeServer {
  _FakeServer(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakeServer> start() async =>
      _FakeServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  /// What `/api/sync` reports as the cursor.
  int cursor = 0;

  /// Which account `/api/me` says the token belongs to.
  String user = 'local';

  /// Rows received, per table, across every request.
  final List<Map<String, List<dynamic>>> pushes = [];

  String get url => 'http://127.0.0.1:${_server.port}';

  int get rowsPushed => pushes.fold(
        0,
        (n, push) => n + push.values.fold<int>(0, (m, rows) => m + rows.length),
      );

  Future<void> _handle(HttpRequest req) async {
    final res = req.response..headers.contentType = ContentType.json;
    if (req.uri.path == '/api/me') {
      res.write(jsonEncode({'user': user, 'label': user, 'admin': false}));
      await res.close();
      return;
    }
    if (req.uri.path == '/api/events') {
      // A successful sync opens a change stream, which is not what any of this
      // is about. 404 is how a server says it does not have the route, and the
      // client's response to that is to stop asking - so this keeps the tests
      // to one connection each. See change_stream_test.dart for the stream.
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }

    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
    final changes = (body['changes'] as Map?) ?? {};
    pushes.add({
      for (final e in changes.entries) e.key as String: e.value as List,
    });
    res.write(jsonEncode({'cursor': cursor, 'changes': {}}));
    await res.close();
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<LocalStore> freshStore() => LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );

  /// A store holding a few rows, all of them already accepted by *some* server.
  /// That is the state the whole problem lives in: clean rows that one database
  /// has and another has never heard of.
  Future<LocalStore> settledStore() async {
    final store = await freshStore();
    final state = AppState(store);
    await state.load();
    await state.addTask('written against the old server');
    await state.addTask('also written against the old server');
    await store.clearDirty(await store.dirtyRows());
    expect(await store.pendingCount(), 0);
    return store;
  }

  /// The re-arm queues a second sync through `_dirtyAgain`, which is
  /// deliberately not awaited - the UI never waits on sync. Give it room to
  /// land before asserting on what reached the server.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  test('a cursor that goes backwards re-arms every row', () async {
    final server = await _FakeServer.start();
    final store = await settledStore();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    // This database has been talking to a server that got to seq 200. The one
    // answering now has never been past 5, so it cannot be the same database.
    await store.setCursor(200);
    server.cursor = 5;

    // Isolate the cursor signal: pin the fingerprint to what this server will
    // report, so the only thing that can fire is the regression check.
    await store.setSetting(kServerFingerprint, '${sync.baseUrl}|local');

    await sync.syncNow();

    expect(await store.pendingCount(), greaterThan(0),
        reason: 'every row should be re-armed for upload');
    expect(await store.cursor(), 0,
        reason: 'the old cursor names a history this server does not have');

    await settle();
    expect(server.rowsPushed, greaterThan(0),
        reason: 'the re-armed rows have to actually go out');
    final texts = server.pushes
        .expand((p) => p['tasks'] ?? const [])
        .map((r) => (r as Map)['text']);
    expect(texts, contains('written against the old server'));

    sync.dispose();
    await store.close();
    await server.stop();
  });

  test('a different account re-arms even when the cursor looks fine', () async {
    final server = await _FakeServer.start();
    final store = await settledStore();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    // A cursor that is only ever going up: the regression check sees nothing
    // wrong, because on its own it cannot tell one account from another.
    await store.setCursor(1);
    server.cursor = 90;
    server.user = 'someone-else';
    await store.setSetting(kServerFingerprint, '${sync.baseUrl}|local');

    await sync.syncNow();
    await settle();

    expect(server.rowsPushed, greaterThan(0),
        reason: 'these rows have never been to this account');
    expect(await store.setting(kServerFingerprint),
        '${sync.baseUrl}|someone-else');

    sync.dispose();
    await store.close();
    await server.stop();
  });

  test('a database that has never been fingerprinted proves itself once',
      () async {
    // The state every existing install upgrades into. There is no way to tell
    // an in-sync copy from one that has been diverging since the last rebuild,
    // so it re-arms rather than assumes - which is what repairs the installs
    // this bug already stranded.
    final server = await _FakeServer.start();
    final store = await settledStore();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    server.cursor = 90;
    expect(await store.setting(kServerFingerprint), isNull);

    await sync.syncNow();
    await settle();

    expect(server.rowsPushed, greaterThan(0));
    expect(await store.setting(kServerFingerprint), '${sync.baseUrl}|local');

    sync.dispose();
    await store.close();
    await server.stop();
  });

  test('a fingerprint that still matches costs nothing', () async {
    // The re-arm must not be something that happens on every launch: it would
    // turn a quiet poll into a full upload of the whole database forever.
    final server = await _FakeServer.start();
    final store = await settledStore();
    final sync = SyncService(store);
    await sync.configure(server.url, 'a-token');

    server.cursor = 90;
    await store.setCursor(12);
    await store.setSetting(kServerFingerprint, '${sync.baseUrl}|local');

    await sync.syncNow();
    await settle();

    expect(await store.pendingCount(), 0, reason: 'nothing to re-send');
    expect(server.rowsPushed, 0);
    expect(await store.cursor(), 90);

    sync.dispose();
    await store.close();
    await server.stop();
  });
}
