// Parked groups.
//
// The invariant worth protecting is that parking is a *move*, not a copy or a
// delete: the same row, keeping its uuid, its history and its reminder, just
// off the current list. Most of these tests are checking that nothing quietly
// disappears on the way in or out.

import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> freshState() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    return state;
  }

  Future<Task> addTask(AppState s, String text) async {
    await s.addTask(text);
    return s.tasks.firstWhere((t) => t.text == text);
  }

  test('a parked task leaves the current list but stays in the workspace',
      () async {
    final s = await freshState();
    final t = await addTask(s, 'rewrite the importer');
    final g = await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);

    await s.parkTask(t, g!.uuid);

    expect(s.tasks, isEmpty);
    expect(s.parked[g.uuid]!.single.uuid, t.uuid);
    // Still one live row, not a new one - parking must not fork the task.
    expect((await s.store.allTasksInWorkspace(t.workspaceUuid)).length, 1);
    await s.store.close();
  });

  test('unparking keeps the same row, and puts it at the bottom of the list',
      () async {
    final s = await freshState();
    final first = await addTask(s, 'first');
    final parked = await addTask(s, 'to be parked');
    final g = await s.saveGroup(title: 'Someday', reviewEveryDays: 30);

    await s.parkTask(parked, g!.uuid);
    await addTask(s, 'added while it was parked');
    await s.unparkTask(s.parked[g.uuid]!.single);

    expect(s.tasks.map((t) => t.text), [
      'first',
      'added while it was parked',
      'to be parked',
    ]);
    expect(s.tasks.last.uuid, parked.uuid);
    expect(s.tasks.first.uuid, first.uuid);
    await s.store.close();
  });

  test('a parked task keeps its reminder but stops firing it', () async {
    final s = await freshState();
    await addTask(s, 'renew the domain');
    await s.setReminder(
      s.tasks.single,
      DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(await s.store.dueReminders(), hasLength(1));

    final g = await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);
    await s.parkTask(s.tasks.single, g!.uuid);

    // Silent while shelved...
    expect(await s.store.dueReminders(), isEmpty);
    expect(await s.store.pendingReminders(), isEmpty);
    // ...but the stamp is still on the row, so unparking arms it again.
    expect(s.parked[g.uuid]!.single.remindAt, isNotNull);

    await s.unparkTask(s.parked[g.uuid]!.single);
    expect(await s.store.dueReminders(), hasLength(1));
    await s.store.close();
  });

  test('parking the focused task drops focus', () async {
    final s = await freshState();
    final t = await addTask(s, 'the thing I am doing');
    await s.enterFocus(t);
    expect(s.focusTask, isNotNull);

    final g = await s.saveGroup(title: 'Later', reviewEveryDays: 30);
    await s.parkTask(s.tasks.single, g!.uuid);

    expect(s.focusTask, isNull);
    expect(await s.store.inProgressTask(), isNull);
    await s.store.close();
  });

  // Activating a whole shelf: unparkGroup. The shelf survives, unlike
  // deleteGroup, and only the open rows move.
  test('activating a group empties it onto the list and keeps the group',
      () async {
    final s = await freshState();
    final a = await addTask(s, 'read the spec');
    final b = await addTask(s, 'draft the reply');
    final g = await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);
    await s.parkTask(a, g!.uuid);
    await s.parkTask(b, g.uuid);

    expect(await s.unparkGroup(g), 2);

    expect(s.tasks.map((t) => t.text), ['read the spec', 'draft the reply']);
    expect(s.parked[g.uuid] ?? const [], isEmpty);
    expect(s.groups.single.uuid, g.uuid, reason: 'the shelf stays');
    await s.store.close();
  });

  test('activating a group appends, in the order the shelf held them',
      () async {
    final s = await freshState();
    final keep = await addTask(s, 'already on the list');
    final first = await addTask(s, 'shelved first');
    final second = await addTask(s, 'shelved second');
    final g = await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);
    await s.parkTask(first, g!.uuid);
    await s.parkTask(second, g.uuid);

    await s.unparkGroup(g);

    expect(s.tasks.map((t) => t.text),
        [keep.text, 'shelved first', 'shelved second']);
    await s.store.close();
  });

  // allTasksInGroup returns completed rows too - deleting a group has to
  // release those as well - so this is the one caller that has to filter.
  test('activating a group leaves its checked-off tasks checked off', () async {
    final s = await freshState();
    final open = await addTask(s, 'still to do');
    final done = await addTask(s, 'done while shelved');
    final g = await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);
    await s.parkTask(open, g!.uuid);
    await s.parkTask(done, g.uuid);
    await s.completeTask(s.parked[g.uuid]!.firstWhere((t) => t.uuid == done.uuid));

    expect(await s.unparkGroup(g), 1);

    expect(s.tasks.map((t) => t.text), ['still to do']);
    final all = await s.store.allTasksInWorkspace(open.workspaceUuid);
    final finished = all.firstWhere((t) => t.uuid == done.uuid);
    expect(finished.completedAt, isNotNull);
    expect(finished.groupUuid, g.uuid, reason: 'it was never unparked');
    await s.store.close();
  });

  test('activating an empty group does nothing and says so', () async {
    final s = await freshState();
    final g = await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);
    expect(await s.unparkGroup(g!), 0);
    expect(s.groups.single.uuid, g.uuid);
    await s.store.close();
  });

  test('deleting a group releases its tasks instead of taking them down',
      () async {
    final s = await freshState();
    final t = await addTask(s, 'a good idea, badly timed');
    final g = await s.saveGroup(title: 'Future ideas', reviewEveryDays: 30);
    await s.parkTask(t, g!.uuid);

    await s.deleteGroup(s.groups.single);

    expect(s.groups, isEmpty);
    expect(s.tasks.single.uuid, t.uuid);
    expect(s.tasks.single.groupUuid, isNull);
    await s.store.close();
  });

  test('deleting a workspace tombstones its groups too', () async {
    final s = await freshState();
    final other = s.workspaces.single;
    await s.saveWorkspace(name: 'Second', color: '#7EE3A1');
    await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);
    expect(s.groups, hasLength(1));

    final second = s.currentWorkspaceUuid!;
    await s.selectWorkspace(other.uuid);
    await s.deleteWorkspace(second);

    expect(await s.store.parkedGroups(second), isEmpty);
    await s.store.close();
  });

  test('groups are scoped to their workspace', () async {
    final s = await freshState();
    final first = s.workspaces.single.uuid;
    await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);

    await s.saveWorkspace(name: 'Second', color: '#7EE3A1');
    expect(s.groups, isEmpty);

    await s.selectWorkspace(first);
    expect(s.groups.single.title, 'Backlog');
    await s.store.close();
  });

  group('review cycle', () {
    ParkedGroup group({
      required String createdAt,
      String? lastReviewedAt,
      int every = 30,
    }) =>
        ParkedGroup(
          uuid: 'g1',
          workspaceUuid: 'ws-1',
          title: 'Backlog',
          reviewEveryDays: every,
          lastReviewedAt: lastReviewedAt,
          createdAt: createdAt,
          updatedAt: createdAt,
        );

    String ago(Duration d) =>
        DateTime.now().subtract(d).toIso8601String();

    test('a new group is not instantly overdue', () {
      expect(group(createdAt: nowStamp()).isReviewDue(), isFalse);
    });

    test('the clock runs from creation until the first review', () {
      expect(group(createdAt: ago(const Duration(days: 31))).isReviewDue(),
          isTrue);
    });

    test('reviewing restarts the clock', () {
      final g = group(
        createdAt: ago(const Duration(days: 90)),
        lastReviewedAt: ago(const Duration(days: 1)),
      );
      expect(g.isReviewDue(), isFalse);
    });

    test('"never" never comes due', () {
      final g = group(createdAt: ago(const Duration(days: 3650)), every: 0);
      expect(g.isReviewDue(), isFalse);
      expect(g.reviewDueAt, isNull);
    });

    test('markGroupReviewed clears the badge', () async {
      final s = await freshState();
      await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);

      // Backdate creation so the group is overdue without waiting a month.
      final stale = s.groups.single;
      await s.store.putGroup(ParkedGroup(
        uuid: stale.uuid,
        workspaceUuid: stale.workspaceUuid,
        title: stale.title,
        reviewEveryDays: stale.reviewEveryDays,
        createdAt: ago(const Duration(days: 40)),
        updatedAt: nowStamp(),
      ));
      await s.refreshTasks();
      expect(s.groupsDueForReview, hasLength(1));

      await s.markGroupReviewed(s.groups.single);
      expect(s.groupsDueForReview, isEmpty);
      await s.store.close();
    });
  });

  test('a database from before parked groups migrates without losing tasks',
      () async {
    // On disk, not in memory: an in-memory database does not outlive its
    // connection, so reopening it would test a fresh schema rather than an
    // upgraded one - which is exactly the bug this is here to catch.
    final dir = await Directory.systemTemp.createTemp('todo_migrate');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'todo.db');

    // v2 is the schema as it shipped with reminders: no parked_groups table and
    // no group_uuid on tasks.
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE tasks (
        uuid           TEXT PRIMARY KEY,
        workspace_uuid TEXT NOT NULL,
        text           TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        completed_at   TEXT,
        sort_order     INTEGER NOT NULL DEFAULT 0,
        in_progress    INTEGER NOT NULL DEFAULT 0,
        remind_at      TEXT,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE workspaces (
        uuid       TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        color      TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        dirty      INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE side_thoughts (
        uuid        TEXT PRIMARY KEY,
        text        TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        resolved_at TEXT,
        updated_at  TEXT NOT NULL,
        deleted_at  TEXT,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute(
        'CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.insert('workspaces', {
      'uuid': 'ws-1',
      'name': 'Tasks',
      'color': '#6c8cff',
      'sort_order': 0,
      'created_at': nowStamp(),
      'updated_at': nowStamp(),
    });
    await db.insert('tasks', {
      'uuid': 't1',
      'workspace_uuid': 'ws-1',
      'text': 'survives the migration',
      'created_at': nowStamp(),
      'updated_at': nowStamp(),
    });
    await db.setVersion(2);
    await db.close();

    final store = await LocalStore.open(path: path, singleInstance: false);
    // 'ws-1' was a seeded default ("Tasks", default colour), so the v9
    // migration folded it onto the canonical workspace and brought its tasks
    // with it - which is the behaviour being relied on here.
    const ws = LocalStore.defaultWorkspaceUuid;
    expect((await store.activeTasks(ws)).single.text, 'survives the migration');
    // The new column reads as "not parked" for every existing row.
    expect((await store.activeTasks(ws)).single.groupUuid, isNull);
    expect(await store.parkedGroups(ws), isEmpty);
    await store.close();
  });
}
