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

  static const _tables = [
    'workspaces',
    'parked_groups',
    'tasks',
    'attachments',
    'side_thoughts',
    'journal_entries',
  ];

  /// [singleInstance] false forces a genuinely new database rather than a
  /// cached handle. sqflite keys its cache on the path, so repeated opens of
  /// `:memory:` otherwise all return the *same* database - which silently
  /// shares state between tests that each believe they are starting clean.
  static Future<LocalStore> open({String? path, bool singleInstance = true}) async {
    // sqflite ships a mobile implementation only; desktop needs the FFI one.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = path ??
        p.join((await getApplicationSupportDirectory()).path, 'todo.db');

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: _create,
        onUpgrade: _upgrade,
        singleInstance: singleInstance,
      ),
    );
    return LocalStore._(db);
  }

  /// Migrations for databases created by an earlier version. There is real user
  /// data behind this - the whole point of the app is that history survives -
  /// so each step only ever adds, never rewrites or drops.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      // Nullable, so every existing row is simply "no reminder". Rows are not
      // marked dirty: adding a column locally is not a user edit, and flagging
      // the entire table would push every task back at the server for nothing.
      await db.execute('ALTER TABLE tasks ADD COLUMN remind_at TEXT');
    }
    if (from < 3) {
      await db.execute(_parkedGroupsTable);
      // Nullable, so every existing task is simply "on the current list".
      await db.execute('ALTER TABLE tasks ADD COLUMN group_uuid TEXT');
      await db.execute(_parkedGroupsIndex);
      await db.execute(_tasksGroupIndex);
    }
    if (from < 4) {
      await db.execute(_attachmentsTable);
      await db.execute(_attachmentsIndex);
    }
    if (from < 5) {
      // The v5 shape, before entries were encrypted and gained a title. The
      // `title` column is added by the from < 6 step below, so a v4 database
      // ends up at the current shape without this create and that alter
      // colliding on the same column.
      await db.execute(_journalTableV5);
      await db.execute(_journalIndex);
    }
    if (from < 6) {
      // Titles arrived alongside the journal's title/body split. NOT NULL needs
      // a default to apply to any existing row; the empty string is a valid
      // "no title".
      await db.execute(
          "ALTER TABLE journal_entries ADD COLUMN title TEXT NOT NULL DEFAULT ''");
    }
    if (from < 7) {
      // Encryption became optional, so each row now records whether its
      // title/text are ciphertext.
      await db.execute(
          'ALTER TABLE journal_entries ADD COLUMN encrypted INTEGER NOT NULL DEFAULT 0');
      // v6 was the short-lived build where the journal was *always* encrypted,
      // so every row it wrote is ciphertext and must be flagged as such - a
      // default of 0 would mislabel it plaintext and render it as garbage.
      // Databases older than v6 only ever held plaintext journal rows, so they
      // correctly keep the 0 default.
      if (from == 6) {
        await db.execute('UPDATE journal_entries SET encrypted = 1');
      }
    }
  }

  /// The v5 journal table, kept verbatim only for the upgrade path from a
  /// database that predated the title column. New databases get [_journalTable]
  /// directly; the title is added to a v5 table by the from < 6 migration.
  static const _journalTableV5 = '''
      CREATE TABLE journal_entries (
        uuid           TEXT PRIMARY KEY,
        workspace_uuid TEXT NOT NULL,
        text           TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''';

  static const _journalTable = '''
      CREATE TABLE journal_entries (
        uuid           TEXT PRIMARY KEY,
        workspace_uuid TEXT NOT NULL,
        title          TEXT NOT NULL DEFAULT '',
        text           TEXT NOT NULL,
        encrypted      INTEGER NOT NULL DEFAULT 0,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''';

  static const _journalIndex =
      'CREATE INDEX idx_journal_ws ON journal_entries (workspace_uuid)';

  static const _attachmentsTable = '''
      CREATE TABLE attachments (
        uuid       TEXT PRIMARY KEY,
        task_uuid  TEXT NOT NULL,
        filename   TEXT NOT NULL,
        size       INTEGER NOT NULL DEFAULT 0,
        sha256     TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        dirty      INTEGER NOT NULL DEFAULT 1
      )''';

  static const _attachmentsIndex =
      'CREATE INDEX idx_attachments_task ON attachments (task_uuid)';

  static const _parkedGroupsTable = '''
      CREATE TABLE parked_groups (
        uuid              TEXT PRIMARY KEY,
        workspace_uuid    TEXT NOT NULL,
        title             TEXT NOT NULL,
        review_every_days INTEGER NOT NULL DEFAULT 30,
        last_reviewed_at  TEXT,
        sort_order        INTEGER NOT NULL DEFAULT 0,
        created_at        TEXT NOT NULL,
        updated_at        TEXT NOT NULL,
        deleted_at        TEXT,
        dirty             INTEGER NOT NULL DEFAULT 1
      )''';

  static const _parkedGroupsIndex =
      'CREATE INDEX idx_groups_ws ON parked_groups (workspace_uuid)';
  static const _tasksGroupIndex =
      'CREATE INDEX idx_tasks_group ON tasks (group_uuid)';

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
        remind_at      TEXT,
        group_uuid     TEXT,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''');

    await db.execute(_parkedGroupsTable);
    await db.execute(_attachmentsTable);
    await db.execute(_journalTable);

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
    await db.execute(_parkedGroupsIndex);
    await db.execute(_tasksGroupIndex);
    await db.execute(_attachmentsIndex);
    await db.execute(_journalIndex);

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

  /// The current list: active, and *not* shelved in a parked group. That
  /// exclusion is the whole point of parking - a backlog item that still showed
  /// up here would not be parked at all.
  Future<List<Task>> activeTasks(String workspaceUuid) async {
    final rows = await _db.query('tasks',
        where: 'workspace_uuid = ? AND completed_at IS NULL '
            'AND deleted_at IS NULL AND group_uuid IS NULL',
        whereArgs: [workspaceUuid],
        orderBy: 'sort_order, created_at');
    return rows.map(Task.fromMap).toList();
  }

  Future<List<ParkedGroup>> parkedGroups(String workspaceUuid) async {
    final rows = await _db.query('parked_groups',
        where: 'workspace_uuid = ? AND deleted_at IS NULL',
        whereArgs: [workspaceUuid],
        orderBy: 'sort_order, created_at');
    return rows.map(ParkedGroup.fromMap).toList();
  }

  /// The still-open tasks shelved in each group of a workspace, keyed by group
  /// uuid. One query rather than one per group: the panel needs every group's
  /// contents at once, and a per-group read would turn opening it into N round
  /// trips for no gain.
  Future<Map<String, List<Task>>> parkedTasks(String workspaceUuid) async {
    final rows = await _db.query('tasks',
        where: 'workspace_uuid = ? AND group_uuid IS NOT NULL '
            'AND completed_at IS NULL AND deleted_at IS NULL',
        whereArgs: [workspaceUuid],
        orderBy: 'sort_order, created_at');

    final out = <String, List<Task>>{};
    for (final t in rows.map(Task.fromMap)) {
      out.putIfAbsent(t.groupUuid!, () => []).add(t);
    }
    return out;
  }

  /// Live tasks shelved in one group, completed ones included. Used when a
  /// group is deleted, which has to release everything it held.
  Future<List<Task>> allTasksInGroup(String groupUuid) async {
    final rows = await _db.query('tasks',
        where: 'group_uuid = ? AND deleted_at IS NULL',
        whereArgs: [groupUuid]);
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

  /// Every live task in a workspace, completed ones included. Used by the
  /// workspace cascade, which must tombstone history too - leaving completed
  /// rows behind would resurrect them in a workspace that no longer exists.
  Future<List<Task>> allTasksInWorkspace(String workspaceUuid) async {
    final rows = await _db.query('tasks',
        where: 'workspace_uuid = ? AND deleted_at IS NULL',
        whereArgs: [workspaceUuid]);
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> inProgressTask() async {
    // Parked tasks are excluded even though [parkTask] clears the flag: a merge
    // can land "parked here" and "focused there" on the same row, and restoring
    // focus onto a task with no row in the list would strand the focus view.
    final rows = await _db.query('tasks',
        where: 'in_progress = 1 AND completed_at IS NULL '
            'AND deleted_at IS NULL AND group_uuid IS NULL',
        orderBy: 'updated_at DESC',
        limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  /// Every armed reminder across *every* workspace - a reminder set in one
  /// workspace has to fire even while another is on screen, or it is not a
  /// reminder.
  ///
  /// Parked tasks are excluded. Parking something says "not now", and firing
  /// would surface a row that is not on the list to be seen; the group's own
  /// review cycle is what nags about a shelf. The stored `remind_at` is kept
  /// either way, so unparking arms it again.
  Future<List<Task>> _armed() async {
    final rows = await _db.query('tasks',
        where: 'remind_at IS NOT NULL AND completed_at IS NULL '
            'AND deleted_at IS NULL AND group_uuid IS NULL',
        orderBy: 'remind_at');
    return rows.map(Task.fromMap).toList();
  }

  /// Reminders already in the past.
  ///
  /// SQL narrows to armed rows; the comparison itself is done in Dart. String
  /// ordering of these stamps is only valid when the offsets match, which stops
  /// being true the moment a phone in another timezone sets one, so the cutoff
  /// is applied on parsed instants instead.
  Future<List<Task>> dueReminders([DateTime? now]) async =>
      (await _armed()).where((t) => t.isDue(now)).toList();

  /// Reminders still ahead, for handing to the OS scheduler on mobile.
  Future<List<Task>> pendingReminders([DateTime? now]) async =>
      (await _armed()).where((t) => !t.isDue(now)).toList();

  Future<Task?> taskByUuid(String uuid) async {
    final rows = await _db
        .query('tasks', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  Future<List<Attachment>> attachmentsFor(String taskUuid) async {
    final rows = await _db.query('attachments',
        where: 'task_uuid = ? AND deleted_at IS NULL',
        whereArgs: [taskUuid],
        orderBy: 'created_at');
    return rows.map(Attachment.fromMap).toList();
  }

  /// How many attachments each task in a workspace has, keyed by task uuid.
  /// Tasks with none are absent rather than mapped to zero.
  ///
  /// One query for the whole list. The paperclip has to render on every row, so
  /// a per-row read would put a query behind every frame of a scroll.
  Future<Map<String, int>> attachmentCounts(String workspaceUuid) async {
    final rows = await _db.rawQuery('''
      SELECT a.task_uuid AS task_uuid, COUNT(*) AS n
        FROM attachments a
        JOIN tasks t ON t.uuid = a.task_uuid
       WHERE t.workspace_uuid = ? AND a.deleted_at IS NULL
       GROUP BY a.task_uuid''', [workspaceUuid]);

    return {
      for (final r in rows)
        r['task_uuid']! as String: (r['n'] as num).toInt(),
    };
  }

  /// Whether any *other* live row still points at these bytes. Attachments are
  /// content-addressed, so two tasks holding the same document share one file
  /// on disk - and deleting one of them must not pull the file out from under
  /// the other.
  Future<bool> isBlobReferenced(String sha256, {String? excludingUuid}) async {
    final rows = await _db.query('attachments',
        where: 'sha256 = ? AND deleted_at IS NULL AND uuid != ?',
        whereArgs: [sha256, excludingUuid ?? ''],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// Every sha256 still referenced by a live row, for sweeping orphaned files.
  Future<Set<String>> referencedBlobs() async {
    final rows = await _db.rawQuery(
        'SELECT DISTINCT sha256 FROM attachments WHERE deleted_at IS NULL');
    return {for (final r in rows) r['sha256']! as String};
  }

  /// A workspace's journal, newest first - the order a running log is read in.
  /// Sorted on `created_at`, not `updated_at`, so editing an old entry does not
  /// yank it back to the top.
  Future<List<JournalEntry>> journalEntries(String workspaceUuid) async {
    final rows = await _db.query('journal_entries',
        where: 'workspace_uuid = ? AND deleted_at IS NULL',
        whereArgs: [workspaceUuid],
        orderBy: 'created_at DESC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// Every live journal entry across all workspaces. Used when turning
  /// encryption on or off, which has to re-encrypt (or decrypt) the whole
  /// journal, not just the workspace on screen - the password is one vault for
  /// all of it.
  Future<List<JournalEntry>> allJournalEntries() async {
    final rows = await _db.query('journal_entries',
        where: 'deleted_at IS NULL', orderBy: 'created_at DESC');
    return rows.map(JournalEntry.fromMap).toList();
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
  Future<void> putGroup(ParkedGroup g) => put('parked_groups', g);
  Future<void> putAttachment(Attachment a) => put('attachments', a);
  Future<void> putJournal(JournalEntry e) => put('journal_entries', e);

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

  /// Persist the manual drag order. Writing every row keeps sort_order dense,
  /// so a later insert cannot land ambiguously between two equal values.
  Future<void> reorderTasks(List<String> uuids) async {
    final stamp = nowStamp();
    await _db.transaction((txn) async {
      for (var i = 0; i < uuids.length; i++) {
        await txn.update(
          'tasks',
          {'sort_order': i, 'updated_at': stamp, 'dirty': 1},
          where: 'uuid = ?',
          whereArgs: [uuids[i]],
        );
      }
    });
  }

  /// Next sort_order for a new task, so it appends rather than jumping to the
  /// top of a manually ordered list.
  Future<int> nextSortOrder(String workspaceUuid) async {
    final rows = await _db.rawQuery(
      'SELECT MAX(sort_order) AS m FROM tasks WHERE workspace_uuid = ?',
      [workspaceUuid],
    );
    return ((rows.first['m'] as num?)?.toInt() ?? -1) + 1;
  }

  Future<int> nextGroupSortOrder(String workspaceUuid) async {
    final rows = await _db.rawQuery(
      'SELECT MAX(sort_order) AS m FROM parked_groups WHERE workspace_uuid = ?',
      [workspaceUuid],
    );
    return ((rows.first['m'] as num?)?.toInt() ?? -1) + 1;
  }

  // --------------------------------------------------------------- settings

  // Small key/value settings (last workspace, nudge toggle, server address)
  // share the sync_state table rather than pulling in another dependency.
  // These are deliberately device-local and never synced: which workspace this
  // device is looking at is not a fact about the todo list.

  Future<String?> setting(String key) async {
    final rows = await _db
        .query('sync_state', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert('sync_state', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearSetting(String key) async {
    await _db.delete('sync_state', where: 'key = ?', whereArgs: [key]);
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

  /// How many local rows are still waiting to reach the server.
  ///
  /// Writes never block on the network, so a server that is off is
  /// indistinguishable from one that is up by looking at the app alone. This
  /// count is what lets the UI say "your work is queued" rather than leaving
  /// the user to guess.
  Future<int> pendingCount() async {
    var total = 0;
    for (final table in _tables) {
      final rows = await _db
          .rawQuery('SELECT COUNT(*) AS n FROM $table WHERE dirty = 1');
      total += (rows.first['n'] as num?)?.toInt() ?? 0;
    }
    return total;
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
