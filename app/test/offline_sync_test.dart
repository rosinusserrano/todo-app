// Working with the server off.
//
// This is the normal case, not the edge case: the sync server is self-hosted,
// so it is off whenever the machine hosting it is. Everything here is about
// the promise that a write made in that window is not lost and not silently
// stuck - it lands on disk, stays flagged, and goes out on the next sync that
// succeeds.
//
// Nothing here needs a server. The unreachable-server tests point at a closed
// port on loopback, which fails immediately rather than waiting for a timeout.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/sync_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<LocalStore> freshStore() => LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );

  /// Nothing listens here. Port 1 is privileged and unbound, so a connection
  /// is refused rather than hanging.
  const deadServer = 'http://127.0.0.1:1';

  /// Let fire-and-forget work finish before the database goes away.
  ///
  /// `resume` deliberately does not await its refresh - the UI must not wait
  /// on it - so a test that closes the store immediately afterwards is racing
  /// its own teardown, not testing anything.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  test('pendingCount counts everything still waiting to go out', () async {
    final store = await freshStore();

    // A fresh database already owes the server its default workspace.
    final atStart = await store.pendingCount();
    expect(atStart, greaterThan(0));

    final state = AppState(store);
    await state.load();
    await state.addTask('written while the laptop was off');
    expect(await store.pendingCount(), greaterThan(atStart));

    await store.clearDirty(await store.dirtyRows());
    expect(await store.pendingCount(), 0);

    await store.close();
  });

  test('a write with the server unreachable is queued, not lost', () async {
    final store = await freshStore();
    final state = AppState(store);
    await state.load();

    final sync = SyncService(store);
    await sync.configure(deadServer, 'any-token');
    await state.addTask('survives the server being down');

    await sync.syncNow();

    // Retryable, not blocked: the server being off is not a config error.
    expect(sync.status, SyncStatus.error);
    expect(sync.pending, greaterThan(0));
    expect(sync.describe(), contains('waiting'));

    // The task is readable exactly as if the sync had worked.
    final tasks = await store.activeTasks(state.workspaces.first.uuid);
    expect(tasks.map((t) => t.text), contains('survives the server being down'));

    // And it is still flagged, so the next successful sync will carry it.
    final dirty = await store.dirtyRows();
    expect(
      dirty['tasks']!.map((r) => r['text']),
      contains('survives the server being down'),
    );

    sync.dispose();
    await store.close();
  });

  test('the queue count survives a restart', () async {
    // The queue is the dirty flag in the database, not a list in memory, so a
    // crash mid-offline must not drop it. A fresh SyncService over the same
    // store stands in for the next launch.
    final store = await freshStore();
    final state = AppState(store);
    await state.load();
    await state.addTask('queued before the crash');

    final before = await store.pendingCount();
    expect(before, greaterThan(0));

    final sync = SyncService(store);
    await sync.load();

    expect(sync.pending, before);

    sync.dispose();
    await store.close();
  });

  test('resume is harmless with no server configured', () async {
    final store = await freshStore();
    final sync = SyncService(store);
    await sync.load();

    expect(sync.status, SyncStatus.off);
    sync.resume();
    expect(sync.status, SyncStatus.off);

    await settle();
    sync.dispose();
    await store.close();
  });

  test('resume does not re-sync on every window focus', () async {
    // Desktop reports a lifecycle resume on each focus change, and this widget
    // is focused constantly - without the gap, alt-tabbing would sync on every
    // return to the window.
    final store = await freshStore();
    final sync = SyncService(store);
    await sync.configure(deadServer, 'any-token');

    sync.lastSynced = DateTime.now();
    sync.status = SyncStatus.ok;
    sync.resume();

    // A sync would have moved it off ok; a skipped one leaves it alone.
    expect(sync.status, SyncStatus.ok);

    await settle();
    sync.dispose();
    await store.close();
  });

  test('a rejected token stops the retries but keeps the queue', () async {
    final store = await freshStore();
    final state = AppState(store);
    await state.load();
    await state.addTask('still mine');

    final sync = SyncService(store);
    await sync.configure(deadServer, 'any-token');
    // Stand in for the server having answered 401.
    sync.status = SyncStatus.blocked;
    sync.message = 'Token rejected.';
    await sync.refreshPending();

    sync.resume();
    expect(sync.status, SyncStatus.blocked);
    expect(sync.describe(), contains('waiting'));
    expect(await store.pendingCount(), greaterThan(0));

    await settle();
    sync.dispose();
    await store.close();
  });
}
