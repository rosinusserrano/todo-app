// Import of the Tauri-era database.
//
// These build a real old-format database on disk rather than mocking one - the
// schema is the whole point of the migration, and a fake that drifts from what
// the Rust build actually wrote would test nothing.

import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/sync/legacy_import.dart';
import 'package:todo_widget/sync/local_store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('legacy_import_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<LocalStore> freshStore() => LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );

  /// The exact schema src-tauri/src/lib.rs left behind, including the columns
  /// that arrived later as ALTER TABLEs.
  Future<String> writeOldDb({
    List<Map<String, Object?>> workspaces = const [
      {'id': 1, 'name': 'Work', 'color': '#ff6c6c', 'sort_order': 0},
      {'id': 2, 'name': 'Uni', 'color': '#7ee3a1', 'sort_order': 1},
    ],
    List<Map<String, Object?>> tasks = const [],
    List<Map<String, Object?>> thoughts = const [],
  }) async {
    final path = p.join(tmp.path, 'todo.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        workspace_id INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        in_progress INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE side_thoughts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )''');
    await db.execute('''
      CREATE TABLE workspaces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )''');

    for (final w in workspaces) {
      await db.insert('workspaces', {
        'created_at': '2026-07-13T10:34:39.579394+02:00',
        ...w,
      });
    }
    for (final t in tasks) {
      await db.insert('tasks', {
        'created_at': '2026-06-19T16:28:30.694193800+02:00',
        ...t,
      });
    }
    for (final s in thoughts) {
      await db.insert('side_thoughts', {
        'created_at': '2026-07-16T11:08:27.341977400+02:00',
        ...s,
      });
    }
    await db.close();
    return path;
  }

  test('brings workspaces, tasks and side thoughts across', () async {
    final source = await writeOldDb(
      tasks: [
        {'text': 'active one', 'workspace_id': 2, 'sort_order': 3},
        {
          'text': 'done one',
          'workspace_id': 1,
          'completed_at': '2026-06-22T18:28:16.339553800+02:00',
        },
      ],
      thoughts: [
        {'text': 'a thought'},
        {'text': 'a resolved thought', 'resolved_at': '2026-07-21T16:40:54+02:00'},
      ],
    );

    final store = await freshStore();
    final result = await LegacyImport.run(store, path: source);

    expect(result.workspaces, 2);
    expect(result.tasks, 2);
    expect(result.thoughts, 2);

    // The default workspace the new database creates is still there, so the
    // old two arrive alongside it rather than replacing it.
    final names = (await store.workspaces()).map((w) => w.name).toList();
    expect(names, containsAll(['Work', 'Uni']));

    final uni = (await store.workspaces()).firstWhere((w) => w.name == 'Uni');
    final active = await store.activeTasks(uni.uuid);
    expect(active.single.text, 'active one');
    expect(active.single.sortOrder, 3);

    final work = (await store.workspaces()).firstWhere((w) => w.name == 'Work');
    expect((await store.history(work.uuid)).single.text, 'done one');

    await store.close();
  });

  test('completed tasks keep the timestamp they were checked off at', () async {
    // History is the reason this app exists; an import that reset every
    // completion to "now" would technically migrate and actually destroy it.
    const doneAt = '2026-06-22T18:28:16.339553800+02:00';
    final source = await writeOldDb(tasks: [
      {'text': 'done one', 'workspace_id': 1, 'completed_at': doneAt},
    ]);

    final store = await freshStore();
    await LegacyImport.run(store, path: source);

    final work = (await store.workspaces()).firstWhere((w) => w.name == 'Work');
    expect((await store.history(work.uuid)).single.completedAt, doneAt);

    await store.close();
  });

  test('imported rows are dirty, so the old history reaches other devices',
      () async {
    final source = await writeOldDb(tasks: [
      {'text': 'one', 'workspace_id': 1},
    ]);

    final store = await freshStore();
    await LegacyImport.run(store, path: source);

    final dirty = await store.dirtyRows();
    expect(dirty['tasks']!.length, 1);
    expect(dirty['workspaces']!.length, 3); // two imported + the default

    await store.close();
  });

  test('runs once and never again', () async {
    final source = await writeOldDb(tasks: [
      {'text': 'one', 'workspace_id': 1},
    ]);

    final store = await freshStore();
    expect((await LegacyImport.run(store, path: source)).tasks, 1);

    final second = await LegacyImport.run(store, path: source);
    expect(second.ranAlready, isTrue);
    expect(second.importedAnything, isFalse);

    final work = (await store.workspaces()).firstWhere((w) => w.name == 'Work');
    expect((await store.activeTasks(work.uuid)).length, 1,
        reason: 'a second run must not duplicate the task');

    await store.close();
  });

  test('leaves the old database untouched', () async {
    final source = await writeOldDb(tasks: [
      {'text': 'one', 'workspace_id': 1},
    ]);
    final before = File(source).readAsBytesSync();

    final store = await freshStore();
    await LegacyImport.run(store, path: source);
    await store.close();

    expect(File(source).readAsBytesSync(), before);
  });

  test('is a no-op when there is no old database', () async {
    final store = await freshStore();
    final result =
        await LegacyImport.run(store, path: p.join(tmp.path, 'nope.db'));

    expect(result.noSource, isTrue);
    expect(result.importedAnything, isFalse);
    // Deliberately not recorded as done: the check is one stat, and marking it
    // would skip a database that only shows up on a later launch.
    expect(await store.setting(LegacyImport.settingKey), isNull);

    await store.close();
  });

  test('keeps focus mode exclusive even if the old database was not', () async {
    final source = await writeOldDb(tasks: [
      {'text': 'one', 'workspace_id': 1, 'in_progress': 1},
      {'text': 'two', 'workspace_id': 1, 'in_progress': 1},
    ]);

    final store = await freshStore();
    await LegacyImport.run(store, path: source);

    expect((await store.inProgressTask())!.text, 'one');
    final flagged = await store.raw
        .query('tasks', where: 'in_progress = 1');
    expect(flagged.length, 1);

    await store.close();
  });

  test('does not carry focus over to an already completed task', () async {
    final source = await writeOldDb(tasks: [
      {
        'text': 'done',
        'workspace_id': 1,
        'in_progress': 1,
        'completed_at': '2026-06-22T18:28:16+02:00',
      },
    ]);

    final store = await freshStore();
    await LegacyImport.run(store, path: source);

    expect(await store.inProgressTask(), isNull);
    await store.close();
  });

  test('rehomes a task whose workspace is missing rather than dropping it',
      () async {
    final source = await writeOldDb(tasks: [
      {'text': 'orphan', 'workspace_id': 99},
    ]);

    final store = await freshStore();
    final result = await LegacyImport.run(store, path: source);
    expect(result.tasks, 1);

    final work = (await store.workspaces()).firstWhere((w) => w.name == 'Work');
    expect((await store.activeTasks(work.uuid)).single.text, 'orphan');

    await store.close();
  });
}
