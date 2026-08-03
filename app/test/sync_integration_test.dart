// End-to-end sync against a real server.
//
// Skipped unless a server address is supplied, so CI (which has no server)
// stays green:
//
//   flutter test --dart-define=SYNC_URL=http://127.0.0.1:8787 \
//                --dart-define=SYNC_TOKEN=<token from the server console>
//
// **Point this at a scratch server, not the one your devices sync with.** Every
// `device()` here is a real client: it pushes its rows into whatever account
// that token belongs to, and they stay there. Running this against the live
// server is how "crossed the wire" and six duplicate "Tasks" workspaces ended
// up in a real account. A throwaway server is one command:
//
//   TODO_SYNC_DB=/tmp/scratch.db TODO_SYNC_PORT=8797 npm run server
//

// This is the only test that exercises the actual wire format. Everything else
// tests one side of it in isolation, which is exactly how a client and server
// end up disagreeing about a field name without either one failing.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/admin_client.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/sync_client.dart';

const _url = String.fromEnvironment('SYNC_URL');
const _token = String.fromEnvironment('SYNC_TOKEN');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> device() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    return state;
  }

  SyncClient client() => SyncClient(baseUrl: _url, token: _token);

  test('the server is reachable and identifies itself', () async {
    final result = await client().checkReachable();
    expect(result, isA<SyncOk>(),
        reason: result is SyncFailed ? result.message : null);
  }, skip: _url.isEmpty ? 'set --dart-define=SYNC_URL to run' : null);

  test('a task added on one device arrives on another', () async {
    final a = await device();
    final b = await device();

    await a.addTask('crossed the wire');
    final pushed = await client().syncOnce(a.store);
    expect(pushed, isA<SyncOk>(),
        reason: pushed is SyncFailed ? pushed.message : null);

    final pulled = await client().syncOnce(b.store);
    expect(pulled, isA<SyncOk>(),
        reason: pulled is SyncFailed ? pulled.message : null);

    await b.refreshWorkspaces();
    await b.refreshTasks();

    // Device B started with its own default workspace, so the incoming task
    // lands in a workspace B was not looking at. Search every workspace.
    final all = <String>[];
    for (final ws in b.workspaces) {
      all.addAll((await b.store.activeTasks(ws.uuid)).map((t) => t.text));
    }
    expect(all, contains('crossed the wire'));
  }, skip: _url.isEmpty ? 'set --dart-define=SYNC_URL to run' : null);

  test('a completion on one device is reflected on the other', () async {
    final a = await device();
    final b = await device();

    await a.addTask('finish the port');
    await client().syncOnce(a.store);
    await client().syncOnce(b.store);

    // A checks it off, then both sync.
    final task = a.tasks.firstWhere((t) => t.text == 'finish the port');
    await a.completeTask(task);
    await client().syncOnce(a.store);
    await client().syncOnce(b.store);

    final row = await b.store.raw
        .query('tasks', where: 'uuid = ?', whereArgs: [task.uuid]);
    expect(row, isNotEmpty, reason: 'the task should have reached device B');
    expect(row.first['completed_at'], isNotNull,
        reason: 'the completion should have followed it');
  }, skip: _url.isEmpty ? 'set --dart-define=SYNC_URL to run' : null);

  test('a delete on one device removes it from the other', () async {
    final a = await device();
    final b = await device();

    await a.addTask('delete me across devices');
    await client().syncOnce(a.store);
    await client().syncOnce(b.store);

    final task = a.tasks.firstWhere((t) => t.text == 'delete me across devices');
    await a.deleteTask(task);
    await client().syncOnce(a.store);
    await client().syncOnce(b.store);

    // The tombstone must have arrived - this is the case a hard delete could
    // never express over the wire.
    final row = await b.store.raw
        .query('tasks', where: 'uuid = ?', whereArgs: [task.uuid]);
    expect(row.first['deleted_at'], isNotNull);

    final visible = await b.store.activeTasks(task.workspaceUuid);
    expect(visible.map((t) => t.text), isNot(contains('delete me across devices')));
  }, skip: _url.isEmpty ? 'set --dart-define=SYNC_URL to run' : null);

  test('the server says which account the token belongs to', () async {
    // admin_client_test.dart stubs this response, so a rename on either side -
    // `admin` becoming `is_admin`, say - passes both unit suites while quietly
    // hiding the user-management panel forever. Only a real server catches it.
    final me = await client().whoAmI();
    expect(me, isNotNull, reason: '/api/me answered nothing');
    expect(me!.user, isNotEmpty);
    expect(me.label, isNotEmpty);
  }, skip: _url.isEmpty ? 'set --dart-define=SYNC_URL to run' : null);

  test('the bootstrap token is an admin, and can list the server\'s people',
      () async {
    // Only meaningful with the token the server printed: that account is the
    // admin. Run with a token minted for someone else and this rightly fails.
    final me = await client().whoAmI();
    expect(me!.admin, isTrue,
        reason: 'SYNC_TOKEN is not the admin account of that server');

    final admin = AdminClient(baseUrl: _url, token: _token);
    final users = await admin.users();
    admin.dispose();

    expect(users, isNotEmpty);
    expect(users.map((u) => u.id), contains(me.user));
    expect(users.where((u) => u.admin), isNotEmpty);
  }, skip: _url.isEmpty ? 'set --dart-define=SYNC_URL to run' : null);
}
