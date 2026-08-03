// The seeded "Tasks" workspace, and the duplicates the old seeding left behind.
//
// The bug this pins: the default workspace used to be seeded with a *generated*
// uuid, so every fresh database - a new phone, a reinstall, every in-memory
// store an integration test opens - produced a different row called "Tasks".
// Sync then behaved perfectly correctly and kept them all, because they were
// not versions of one row; they were different rows. A real account ended up
// with seven.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<LocalStore> fresh() =>
      LocalStore.open(path: inMemoryDatabasePath, singleInstance: false);

  test('a fresh database seeds the canonical workspace', () async {
    final store = await fresh();
    final ws = (await store.workspaces()).single;
    expect(ws.uuid, LocalStore.defaultWorkspaceUuid);
    expect(ws.name, 'Tasks');
    await store.close();
  });

  test('two fresh databases seed the SAME row, not two siblings', () async {
    // This is the whole fix. Before it, these two uuids differed, and syncing
    // the two devices together produced two "Tasks" workspaces with no rule
    // that could ever merge them.
    final a = await fresh();
    final b = await fresh();

    expect((await a.workspaces()).single.uuid, (await b.workspaces()).single.uuid);

    await a.close();
    await b.close();
  });

  group('folding the duplicates already out there', () {
    /// A v8 database holding [strays] extra seeded defaults, as sync would have
    /// delivered them from other devices, plus whatever [seed] writes.
    ///
    /// The canonical row a v9 `_create` seeds is removed: a database from
    /// before the fix had a *generated* id for its own default, which is the
    /// state the migration has to cope with. Everything - including the
    /// content - has to be in place before the database is reopened, because
    /// that reopen is the migration.
    Future<String> databaseWithStrays(
      Directory dir,
      List<Map<String, Object?>> strays, {
      Future<void> Function(LocalStore)? seed,
    }) async {
      final path = p.join(dir.path, 'todo.db');
      final store = await LocalStore.open(path: path, singleInstance: false);

      await store.raw.delete('workspaces',
          where: 'uuid = ?', whereArgs: [LocalStore.defaultWorkspaceUuid]);

      for (final stray in strays) {
        await store.raw.insert('workspaces', {
          'name': 'Tasks',
          'color': '#6c8cff',
          'sort_order': 0,
          'created_at': '2026-07-21T21:37:15.000000',
          'updated_at': '2026-07-21T21:37:15.000000',
          'deleted_at': null,
          'dirty': 0,
          ...stray,
        });
      }
      await seed?.call(store);

      // Roll back so the next open runs the v9 migration. v9 adds no tables,
      // but v10 adds tasks.event_uuid, so that column (and the index on it,
      // which SQLite will not let the column be dropped under) has to go too.
      await store.raw.execute('DROP INDEX idx_tasks_event');
      await store.raw.execute('ALTER TABLE tasks DROP COLUMN event_uuid');
      await store.raw.setVersion(8);
      await store.close();
      return path;
    }

    test('strays are tombstoned and their contents move to the canonical row',
        () async {
      final dir = Directory.systemTemp.createTempSync('todo-fold-');
      // Content spread across the strays, exactly like the real account: a task
      // in one, a journal entry and a calendar event in another.
      final path = await databaseWithStrays(
        dir,
        [
          {'uuid': 'stray-1'},
          {'uuid': 'stray-2'},
        ],
        seed: (store) async {
          await store.putTask(Task(
            uuid: 't-1',
            workspaceUuid: 'stray-1',
            text: 'crossed the wire',
            createdAt: nowStamp(),
            updatedAt: nowStamp(),
          ));
          await store.raw.insert('journal_entries', {
            'uuid': 'j-1',
            'workspace_uuid': 'stray-2',
            'title': 'note',
            'text': 'kept',
            'encrypted': 0,
            'created_at': nowStamp(),
            'updated_at': nowStamp(),
            'dirty': 0,
          });
          await store.raw.insert('calendar_events', {
            'uuid': 'e-1',
            'calendar_uuid': 'stray-2', // a workspace calendar carries its uuid
            'title': 'standup',
            'start_at': '2026-08-03T09:00:00.000Z',
            'end_at': '2026-08-03T09:30:00.000Z',
            'created_at': nowStamp(),
            'updated_at': nowStamp(),
            'dirty': 0,
          });
        },
      );

      final store = await LocalStore.open(path: path, singleInstance: false);

      // One workspace left, and it is the canonical one.
      final alive = await store.workspaces();
      expect(alive.length, 1);
      expect(alive.single.uuid, LocalStore.defaultWorkspaceUuid);

      // Nothing was thrown away - it was re-parented.
      final tasks = await store.activeTasks(LocalStore.defaultWorkspaceUuid);
      expect(tasks.single.text, 'crossed the wire');
      final journal = await store.raw
          .query('journal_entries', where: 'uuid = ?', whereArgs: ['j-1']);
      expect(journal.single['workspace_uuid'], LocalStore.defaultWorkspaceUuid);
      final events = await store.raw
          .query('calendar_events', where: 'uuid = ?', whereArgs: ['e-1']);
      expect(events.single['calendar_uuid'], LocalStore.defaultWorkspaceUuid);

      // The husks are tombstones, not disappearances, so the other devices
      // learn about the collapse instead of re-pushing their copies forever.
      final husks = await store.raw.query('workspaces',
          where: 'uuid IN (?, ?)', whereArgs: ['stray-1', 'stray-2']);
      expect(husks.length, 2);
      for (final husk in husks) {
        expect(husk['deleted_at'], isNotNull);
        expect(husk['dirty'], 1, reason: 'the tombstone has to be pushed');
      }

      await store.close();
      dir.deleteSync(recursive: true);
    });

    test('a workspace the user renamed or recoloured is left alone', () async {
      final dir = Directory.systemTemp.createTempSync('todo-fold-');
      final path = await databaseWithStrays(dir, [
        {'uuid': 'stray-1'},
        // Same seed originally, but the user made it theirs. Folding it would
        // be destroying a deliberate choice, so the match is on both fields.
        {'uuid': 'mine-1', 'name': 'Work', 'color': '#6c8cff'},
        {'uuid': 'mine-2', 'name': 'Tasks', 'color': '#ff6c6c'},
      ]);

      final store = await LocalStore.open(path: path, singleInstance: false);
      final alive = (await store.workspaces()).map((w) => w.uuid).toList();

      expect(alive, contains('mine-1'));
      expect(alive, contains('mine-2'));
      expect(alive, contains(LocalStore.defaultWorkspaceUuid));
      expect(alive, isNot(contains('stray-1')));

      await store.close();
      dir.deleteSync(recursive: true);
    });

    test('the oldest stray donates its sort order and creation date', () async {
      final dir = Directory.systemTemp.createTempSync('todo-fold-');
      final path = await databaseWithStrays(dir, [
        {
          'uuid': 'stray-old',
          'created_at': '2026-01-01T09:00:00.000000',
          'sort_order': 2,
        },
        {'uuid': 'stray-new', 'created_at': '2026-07-21T21:37:16.000000'},
      ]);

      final store = await LocalStore.open(path: path, singleInstance: false);
      final canonical = (await store.workspaces())
          .firstWhere((w) => w.uuid == LocalStore.defaultWorkspaceUuid);

      // The workspace keeps the position it has been sitting in, rather than
      // jumping to the front of the bar on upgrade.
      expect(canonical.sortOrder, 2);
      expect(canonical.createdAt, '2026-01-01T09:00:00.000000');

      await store.close();
      dir.deleteSync(recursive: true);
    });

    test('running the migration again changes nothing', () async {
      final dir = Directory.systemTemp.createTempSync('todo-fold-');
      final path = await databaseWithStrays(dir, [
        {'uuid': 'stray-1'},
      ]);

      var store = await LocalStore.open(path: path, singleInstance: false);
      final after = (await store.workspaces()).single.uuid;
      // A second device that syncs the tombstones and then upgrades must not
      // find "duplicates" to fold all over again. The first open just ran the
      // v10 step, so its column and index have to come back off before the
      // version does.
      await store.raw.execute('DROP INDEX idx_tasks_event');
      await store.raw.execute('ALTER TABLE tasks DROP COLUMN event_uuid');
      await store.raw.setVersion(8);
      await store.close();

      store = await LocalStore.open(path: path, singleInstance: false);
      expect((await store.workspaces()).single.uuid, after);

      await store.close();
      dir.deleteSync(recursive: true);
    });
  });
}
