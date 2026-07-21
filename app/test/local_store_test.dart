// Local store + merge tests. Run with: flutter test
//
// These cover the offline/merge behaviour that is painful to reproduce by hand
// once the app is on a phone.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // singleInstance: false so each test gets its own database rather than a
  // cached handle to a shared one.
  Future<LocalStore> freshStore() => LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );

  Task sampleTask(String uuid, String text, String updatedAt) => Task(
        uuid: uuid,
        workspaceUuid: 'ws-1',
        text: text,
        createdAt: '2026-07-21T10:00:00.000',
        updatedAt: updatedAt,
      );

  test('a new database has one workspace so tasks can always be added',
      () async {
    final store = await freshStore();
    expect((await store.workspaces()).length, 1);
    await store.close();
  });

  test('locally written rows are marked dirty and show up for push', () async {
    final store = await freshStore();
    await store.putTask(sampleTask('t1', 'buy milk', nowStamp()));

    final dirty = await store.dirtyRows();
    expect(dirty['tasks']!.length, 1);
    expect(dirty['tasks']!.first['text'], 'buy milk');
    // The default workspace is dirty too - it has never been pushed.
    expect(dirty['workspaces']!.length, 1);
    await store.close();
  });

  test('clearDirty only clears the exact version that was pushed', () async {
    final store = await freshStore();
    await store.putTask(sampleTask('t1', 'original', '2026-07-21T10:00:00.000'));
    final pushed = await store.dirtyRows();

    // The user edits the task while the push is still in flight.
    await store.putTask(sampleTask('t1', 'edited mid-flight', '2026-07-21T10:00:05.000'));
    await store.clearDirty(pushed);

    // The newer edit must still be pending, not silently marked clean.
    final stillDirty = await store.dirtyRows();
    final texts = stillDirty['tasks']!.map((r) => r['text']).toList();
    expect(texts, contains('edited mid-flight'));
    await store.close();
  });

  test('a newer remote row overwrites a clean local row', () async {
    final store = await freshStore();
    await store.putTask(sampleTask('t1', 'local', '2026-07-21T10:00:00.000'));
    await store.clearDirty(await store.dirtyRows());

    await store.applyRemote({
      'tasks': [
        sampleTask('t1', 'from server', '2026-07-21T11:00:00.000').toMap(),
      ],
    });

    final tasks = await store.activeTasks('ws-1');
    expect(tasks.single.text, 'from server');
    await store.close();
  });

  test('an older remote row never clobbers a newer local edit', () async {
    final store = await freshStore();
    await store.putTask(sampleTask('t1', 'local edit', '2026-07-21T12:00:00.000'));

    // Server replies with a stale copy it had not yet heard about.
    await store.applyRemote({
      'tasks': [sampleTask('t1', 'stale server copy', '2026-07-21T09:00:00.000').toMap()],
    });

    final tasks = await store.activeTasks('ws-1');
    expect(tasks.single.text, 'local edit',
        reason: 'a pending local change must not be discarded');
    await store.close();
  });

  test('tombstones from the server remove the task from the active list',
      () async {
    final store = await freshStore();
    await store.putTask(sampleTask('t1', 'doomed', '2026-07-21T10:00:00.000'));
    await store.clearDirty(await store.dirtyRows());

    await store.applyRemote({
      'tasks': [
        {
          ...sampleTask('t1', 'doomed', '2026-07-21T13:00:00.000').toMap(),
          'deleted_at': '2026-07-21T13:00:00.000',
        }
      ],
    });

    expect(await store.activeTasks('ws-1'), isEmpty);
    await store.close();
  });

  test('setInProgress is exclusive across tasks', () async {
    final store = await freshStore();
    await store.putTask(sampleTask('t1', 'one', nowStamp()));
    await store.putTask(sampleTask('t2', 'two', nowStamp()));

    await store.setInProgress('t1', true);
    expect((await store.inProgressTask())!.uuid, 't1');

    await store.setInProgress('t2', true);
    final focused = await store.inProgressTask();
    expect(focused!.uuid, 't2');

    final all = await store.activeTasks('ws-1');
    expect(all.where((t) => t.inProgress).length, 1);
    await store.close();
  });

  test('completed tasks leave the active list but stay in history', () async {
    final store = await freshStore();
    final t = sampleTask('t1', 'ship it', nowStamp());
    await store.putTask(t);
    await store.putTask(t.copyWith(completedAt: nowStamp()));

    expect(await store.activeTasks('ws-1'), isEmpty);
    expect((await store.history('ws-1')).single.text, 'ship it');
    await store.close();
  });

  test('timestamps compare as instants, not strings, across offsets', () {
    // 09:00+02:00 is 07:00Z, which is *earlier* than 08:00Z despite sorting
    // later as a plain string. A phone changing timezone hits exactly this.
    expect(compareStamps('2026-07-21T09:00:00+02:00', '2026-07-21T08:00:00Z'),
        lessThan(0));
  });
}
