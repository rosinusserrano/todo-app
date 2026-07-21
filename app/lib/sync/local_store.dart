// Local database. Mirrors the server schema (server/db.js) plus two columns
// the server does not need:
//
//   dirty      - this row changed locally and has not been accepted by the
//                server yet. Pushing "everything newer than the last sync
//                time" instead would drop writes whenever the device clock
//                moves backwards, which is why this is an explicit flag.
//   (cursor)   - stored in sync_state, the last seq the server handed us.
//
// The app reads and writes only this database and works fully offline. Sync is
// a background reconciliation on top, never something the UI waits for.

import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// sqflite_common_ffi re-exports sqflite's API, so one import covers both. The
// `sqflite` package stays in pubspec.yaml regardless: it registers the native
// plugin used on iOS and Android.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models.dart';

class LocalStore {
  LocalStore._(this._db);

  final Database _db;

  Database get raw => _db;

  static const _tables = ['workspaces', 'tasks', 'side_thoughts'];

  static Future<LocalStore> open({String? path}) async {
    // sqflite ships a mobile implementation only; desktop needs the FFI one.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = path ??
        p.join((await getApplicationSupportDirectory()).path, 'todo.db');

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 1, onCreate: _create),
    );
    return LocalStore._(db);
  }

  static Future<void> _create(Database db, int version) async {
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
      CREATE TABLE tasks (
        uuid           TEXT PRIMARY KEY,
        workspace_uuid TEXT NOT NULL,
        text           TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        completed_at   TEXT,
        sort_order     INTEGER NOT NULL DEFAULT 0,
        in_progress    INTEGER NOT NULL DEFAULT 0,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
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

    await db.execute('''
      CREATE TABLE sync_state (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    await db.insert('sync_state', {'key': 'cursor', 'value': '0'});

    await db.execute('CREATE INDEX idx_tasks_ws ON tasks (workspace_uuid)');
    await db.execute('CREATE INDEX idx_tasks_dirty ON tasks (dirty)');

    // A first workspace, so the app is never in a state with nowhere to add a
    // task. Sync merges it with any peer's default by uuid, so two devices
    // that both start fresh will end up with two - acceptable, and far less
    // confusing than an app that refuses to accept input.
    final now = nowStamp();
    await db.insert('workspaces', {
      'uuid': newId(),
      'name': 'Tasks',
      'color': '#6c8cff',
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'dirty': 1,
    });
  }

  // ------------------------------------------------------------------ reads

  Future<List<Workspace>> workspaces() async {
    final rows = await _db.query('workspaces',
        where: 'deleted_at IS NULL', orderBy: 'sort_order, created_at');
    return rows.map(Workspace.fromMap).toList();
  }

  Future<List<Task>> activeTasks(String workspaceUuid) async {
    final rows = await _db.query('tasks',
        where: 'workspace_uuid = ? AND completed_at IS NULL AND deleted_at IS NULL',
        whereArgs: [workspaceUuid],
        orderBy: 'sort_order, created_at');
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> history(String workspaceUuid, {int limit = 100}) async {
    final rows = await _db.query('tasks',
        where:
            'workspace_uuid = ? AND completed_at IS NOT NULL AND deleted_at IS NULL',
        whereArgs: [workspaceUuid],
        orderBy: 'completed_at DESC',
        limit: limit);
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> inProgressTask() async {
    final rows = await _db.query('tasks',
        where: 'in_progress = 1 AND completed_at IS NULL AND deleted_at IS NULL',
        orderBy: 'updated_at DESC',
        limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  Future<List<SideThought>> pendingThoughts() async {
    final rows = await _db.query('side_thoughts',
        where: 'resolved_at IS NULL AND deleted_at IS NULL',
        orderBy: 'created_at');
    return rows.map(SideThought.fromMap).toList();
  }

  // ----------------------------------------------------------------- writes

  /// Every local write goes through here so nothing can be saved without being
  /// marked dirty - a row that misses the flag would never sync, and the bug
  /// would only show up on a second device.
  Future<void> put(String table, SyncRow row) async {
    await _db.insert(
      table,
      {...row.toMap(), 'dirty': 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> putTask(Task t) => put('tasks', t);
  Future<void> putWorkspace(Workspace w) => put('workspaces', w);
  Future<void> putThought(SideThought s) => put('side_thoughts', s);

  /// Focus mode is globally exclusive: flagging one task clears every other.
  Future<void> setInProgress(String uuid, bool value) async {
    final stamp = nowStamp();
    await _db.transaction((txn) async {
      if (value) {
        await txn.rawUpdate(
          'UPDATE tasks SET in_progress = 0, updated_at = ?, dirty = 1 '
          'WHERE in_progress = 1 AND uuid != ?',
          [stamp, uuid],
        );
      }
      await txn.update(
        'tasks',
        {'in_progress': value ? 1 : 0, 'updated_at': stamp, 'dirty': 1},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
    });
  }

  // ------------------------------------------------------------------- sync

  Future<int> cursor() async {
    final rows = await _db
        .query('sync_state', where: 'key = ?', whereArgs: ['cursor'], limit: 1);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
  }

  Future<void> setCursor(int value) async {
    await _db.insert('sync_state', {'key': 'cursor', 'value': '$value'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Rows changed locally since the last accepted push.
  Future<Map<String, List<Map<String, Object?>>>> dirtyRows() async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      final rows = await _db.query(table, where: 'dirty = 1');
      out[table] = rows.map((r) {
        final m = Map<String, Object?>.from(r);
        m.remove('dirty');
        return m;
      }).toList();
    }
    return out;
  }

  /// Apply rows coming back from the server, last-write-wins on `updated_at`.
  ///
  /// A local row that is still dirty and strictly newer than the server's copy
  /// is kept: the server has simply not seen our edit yet, and it will win on
  /// the next push. Overwriting it here would silently discard a local change
  /// the user just made.
  Future<void> applyRemote(
      Map<String, List<Map<String, Object?>>> changes) async {
    await _db.transaction((txn) async {
      for (final table in _tables) {
        for (final remote in changes[table] ?? const []) {
          final uuid = remote['uuid'] as String;
          final existing = await txn
              .query(table, where: 'uuid = ?', whereArgs: [uuid], limit: 1);

          if (existing.isNotEmpty) {
            final localUpdated = existing.first['updated_at'] as String;
            final localDirty =
                ((existing.first['dirty'] as num?)?.toInt() ?? 0) != 0;
            final remoteUpdated = remote['updated_at'] as String;

            if (localDirty &&
                compareStamps(localUpdated, remoteUpdated) > 0) {
              continue;
            }
            if (compareStamps(remoteUpdated, localUpdated) < 0) continue;
          }

          final row = Map<String, Object?>.from(remote)
            ..remove('seq')
            ..['dirty'] = 0;
          await txn.insert(table, row,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  /// Clear the dirty flag on rows the server accepted.
  ///
  /// Scoped to the exact `updated_at` that was pushed. If the user edited the
  /// row again while the request was in flight, the flag stays set and the new
  /// edit goes out on the next sync instead of being lost.
  Future<void> clearDirty(
      Map<String, List<Map<String, Object?>>> pushed) async {
    await _db.transaction((txn) async {
      for (final table in _tables) {
        for (final row in pushed[table] ?? const []) {
          await txn.update(
            table,
            {'dirty': 0},
            where: 'uuid = ? AND updated_at = ?',
            whereArgs: [row['uuid'], row['updated_at']],
          );
        }
      }
    });
  }

  Future<void> close() => _db.close();
}
