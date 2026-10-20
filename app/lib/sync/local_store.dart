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

// Written against the sqflite API alone; which implementation backs it (FFI on
// desktop, the plugin on mobile, WASM in a browser) is db_factory.dart's call.
import 'dart:typed_data';

import 'package:sqflite_common/sqflite.dart';

import 'db_factory.dart';
import 'models.dart';

class LocalStore {
  LocalStore._(this._db);

  final Database _db;

  Database get raw => _db;

  /// The uuid of the workspace every fresh database seeds.
  ///
  /// **Fixed, not generated**, and that is the whole point. A generated one
  /// meant every fresh database - a new phone, a reinstall, each in-memory
  /// store an integration test opens - seeded a *different* row that happened
  /// to be called "Tasks". Sync then did exactly what it should: merged by
  /// uuid, found no match, and kept both. Six test runs against a real server
  /// left seven "Tasks" workspaces that no merge rule could ever fold, because
  /// they were not versions of one row - they were different rows.
  ///
  /// Deriving the id instead of generating it is the same trick
  /// [Calendar.forWorkspace] uses for a workspace's calendar, and for the same
  /// reason: two devices provisioning the same thing while offline have to
  /// produce the same row, or sync can only ever see siblings.
  ///
  /// The value is a valid v4-shaped uuid so it cannot collide with a generated
  /// one, and is recognisable on sight when reading rows by hand.
  static const defaultWorkspaceUuid = '00000000-0000-4000-8000-000000000001';

  /// What the seeded default looks like, and therefore what the v9 migration
  /// recognises as "a default someone else's device seeded".
  static const _defaultWorkspaceName = 'Tasks';
  static const _defaultWorkspaceColor = '#6c8cff';

  static const _tables = [
    'workspaces',
    'parked_groups',
    'tasks',
    'attachments',
    'side_thoughts',
    'journal_entries',
    'calendars',
    'calendar_events',
    'calendar_feeds',
    'lists',
    'list_items',
    'collections',
    'collection_fields',
    'collection_entries',
  ];

  /// [singleInstance] false forces a genuinely new database rather than a
  /// cached handle. sqflite keys its cache on the path, so repeated opens of
  /// `:memory:` otherwise all return the *same* database - which silently
  /// shares state between tests that each believe they are starting clean.
  /// [seedWorkspace] puts a first "Tasks" workspace into a database created
  /// here. The app opens with it **off** - a new account starts with no
  /// workspace and the list explains what to make (ui/no_workspace.dart,
  /// Marco 2026-10-20) - and the test fixtures keep it on, since most of
  /// them want somewhere to put a task.
  static Future<LocalStore> open({
    String? path,
    bool singleInstance = true,
    bool seedWorkspace = true,
  }) async {
    await initDatabaseFactory();
    final dbPath = path ?? await defaultDatabasePath();

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 22,
        onCreate: (db, version) =>
            _create(db, version, seedWorkspace: seedWorkspace),
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
      await db.execute(_attachmentsTableV4);
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
    if (from < 8) {
      await db.execute(_calendarsTable);
      await db.execute(_calendarEventsTableV8);
      await db.execute(_calendarsWsIndex);
      await db.execute(_eventsCalendarIndex);
      await db.execute(_eventsStartIndex);
      // Attachments grew a second possible owner. Nullable, so every existing
      // row stays exactly what it was: an attachment on a task.
      await db.execute('ALTER TABLE attachments ADD COLUMN event_uuid TEXT');
      await db.execute(_attachmentsEventIndex);
    }
    if (from < 9) {
      await _foldSeededDefaults(db);
    }
    if (from < 10) {
      // Tasks can be planned into a block of time. Nullable, so every existing
      // task is simply "not planned into anything".
      await db.execute('ALTER TABLE tasks ADD COLUMN event_uuid TEXT');
      await db.execute(_tasksEventIndex);
    }
    if (from < 11) {
      // The long form, and the flag. Both NOT NULL with a default that is
      // exactly what every existing row means: no notes, ordinary priority.
      // One step for the two of them - they landed together, and a second
      // migration for a second column would be a second thing to test.
      await db.execute(
          "ALTER TABLE tasks ADD COLUMN notes TEXT NOT NULL DEFAULT ''");
      await db.execute(
          'ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 0');
    }
    if (from < 12) {
      // Recurrence. Nullable, and null is exactly what every existing row
      // means: a one-off. No backfill, and nothing else to migrate - the rule
      // is the only new state, because the next occurrence is a new row rather
      // than a second set of columns on this one.
      await db.execute('ALTER TABLE tasks ADD COLUMN recur TEXT');
    }
    if (from < 13) {
      // The same column on a block of time, and the same "null means one-off".
      // Unlike a task, a repeating block stays *one* row: its occurrences are
      // expanded on the way out of the store and never written, so there is
      // nothing here to backfill either.
      await db.execute('ALTER TABLE calendar_events ADD COLUMN recur TEXT');
    }
    if (from < 14) {
      // Whole days. NOT NULL with a default that is what every existing row
      // means - a span of hours - so there is no third state to reason about.
      // The instants are unchanged: an all-day event is one that runs from
      // midnight to midnight, and this says to *draw* it as a day rather than
      // as a very long meeting.
      await db.execute(
          'ALTER TABLE calendar_events ADD COLUMN all_day INTEGER NOT NULL DEFAULT 0');
    }
    if (from < 15) {
      // Recurrence grew from one column to four, and every default here is
      // exactly what an existing recurring task already means:
      //
      //   recur_from  'schedule'  - it was always measured from the due date.
      //   recur_lead  null        - the successor appeared when this one was
      //                             ticked, which is what null goes on meaning.
      //   recur_text  null        - the text is its own template; no row
      //   recur_notes null          written before this had a variable in it.
      //
      // So there is nothing to backfill, and a task that has always repeated
      // goes on repeating in exactly the way it did.
      // Nullable rather than NOT NULL DEFAULT 'schedule' - see the note in
      // _create. Task.fromMap is what turns null into 'schedule'.
      await db.execute('ALTER TABLE tasks ADD COLUMN recur_from TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN recur_lead INTEGER');
      await db.execute('ALTER TABLE tasks ADD COLUMN recur_text TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN recur_notes TEXT');
      await db.execute(_tasksRecurIndex);
    }
    if (from < 16) {
      // Subscribed calendars. The subscription is a table of its own; its
      // events are ordinary calendar_events rows marked with the feed that
      // wrote them. Null is what every existing event means - made here - so
      // there is nothing to backfill.
      await db.execute(_calendarFeedsTable);
      await db.execute('ALTER TABLE calendar_events ADD COLUMN feed_uuid TEXT');
      await db.execute(_eventsFeedIndex);
      // Pull everything once more. A protocol-1 build is not sent feed_uuid or
      // the feeds table, and its cursor walked past those rows all the same;
      // starting over is what brings them in now that it can store them. Ties
      // are re-applied by applyRemote, so it fills in what was held back and
      // changes nothing else.
      await db.update('sync_state', {'value': '0'},
          where: 'key = ?', whereArgs: ['cursor']);
    }
    if (from < 17) {
      // The shopping list. Two new tables and nothing to backfill; the cursor
      // reset v16 does is not needed again here, since no server below
      // protocol 3 has these tables to have held anything back.
      await db.execute(_listsTable);
      await db.execute(_listItemsTable);
      await db.execute(_listItemsIndex);
    }
    if (from < 18) {
      // Collections. Three new tables and nothing to backfill, for the reason
      // v17 gave: no server below protocol 4 has them to have held anything
      // back.
      await db.execute(_collectionsTable);
      await db.execute(_collectionFieldsTable);
      await db.execute(_collectionEntriesTable);
      await db.execute(_collectionsWorkspaceIndex);
      await db.execute(_collectionFieldsIndex);
      await db.execute(_collectionEntriesIndex);
    }
    if (from < 19) {
      // A workspace's shortcuts in a task's title (`#MT`). Null is "none",
      // which is what every existing workspace has. The cursor goes back to
      // the start for v16's reason: a build below protocol 5 is not sent the
      // column, and its cursor walked past the rows that carry it.
      await db.execute('ALTER TABLE workspaces ADD COLUMN shortcuts TEXT');
      await db.update('sync_state', {'value': '0'},
          where: 'key = ?', whereArgs: ['cursor']);
    }
    if (from < 20) {
      // Voice notes: a thought said aloud, and the task it becomes. Null is
      // "typed", which is every existing row. The bytes go in `blobs`, which
      // is this device's and never syncs. The cursor goes back for v16's
      // reason again: a build below protocol 6 is not sent the columns.
      await db.execute('ALTER TABLE side_thoughts ADD COLUMN audio TEXT');
      await db.execute('ALTER TABLE side_thoughts ADD COLUMN audio_ms INTEGER');
      await db.execute('ALTER TABLE tasks ADD COLUMN audio TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN audio_ms INTEGER');
      await db.execute(_blobsTable);
      await db.update('sync_state', {'value': '0'},
          where: 'key = ?', whereArgs: ['cursor']);
    }
    if (from < 21) {
      // Projects: a workspace with a parent, and its archive. Null is "a
      // workspace" and "not archived", which is every existing row. The
      // cursor goes back for v16's reason: below protocol 7 the server does
      // not send the columns.
      await db.execute('ALTER TABLE workspaces ADD COLUMN parent_uuid TEXT');
      await db.execute('ALTER TABLE workspaces ADD COLUMN archived_at TEXT');
      await db.update('sync_state', {'value': '0'},
          where: 'key = ?', whereArgs: ['cursor']);
    }
    if (from < 22) {
      // A reminder on a thought. Null is "none", which is every existing row.
      // The cursor goes back for v16's reason: below protocol 8 the server
      // does not send the column.
      await db.execute('ALTER TABLE side_thoughts ADD COLUMN remind_at TEXT');
      await db.update('sync_state', {'value': '0'},
          where: 'key = ?', whereArgs: ['cursor']);
    }
  }

  /// Collapse every seeded "Tasks" workspace onto [defaultWorkspaceUuid].
  ///
  /// The clean-up half of the fix above: the duplicates already out there were
  /// created before the id was fixed, so nothing about the new id retires them
  /// on its own. This moves their contents onto the canonical row and
  /// tombstones the husks.
  ///
  /// Three things make it safe to run against real data:
  ///
  ///   - It only touches rows that look exactly like something *we* seeded
  ///     (the default name and colour). A renamed or recoloured workspace is
  ///     the user's, and is left alone even if that means it sits beside the
  ///     canonical one.
  ///   - Nothing is deleted, only re-parented. Tasks, shelves, journal entries
  ///     and events move across; the empty workspace is then tombstoned.
  ///   - Every row it moves is marked dirty, so the collapse propagates to the
  ///     other devices as ordinary edits and tombstones rather than having to
  ///     be repeated there.
  static Future<void> _foldSeededDefaults(Database db) async {
    final seeded = await db.query(
      'workspaces',
      where: 'name = ? AND color = ? AND deleted_at IS NULL',
      whereArgs: [_defaultWorkspaceName, _defaultWorkspaceColor],
      orderBy: 'created_at',
    );
    if (seeded.isEmpty) return;

    final strays = seeded.where((w) => w['uuid'] != defaultWorkspaceUuid).toList();
    if (strays.isEmpty) return;

    final now = nowStamp();

    // The canonical row may not exist yet - on this database the seed that ran
    // at install time had a generated id. Promote the oldest stray's own
    // details rather than inventing new ones, so a workspace that has been
    // sorted somewhere specific stays there.
    final canonical = seeded.firstWhere(
      (w) => w['uuid'] == defaultWorkspaceUuid,
      orElse: () => const {},
    );
    if (canonical.isEmpty) {
      final oldest = strays.first;
      await db.insert('workspaces', {
        'uuid': defaultWorkspaceUuid,
        'name': _defaultWorkspaceName,
        'color': _defaultWorkspaceColor,
        'sort_order': oldest['sort_order'],
        'created_at': oldest['created_at'],
        'updated_at': now,
        'deleted_at': null,
        'dirty': 1,
      });
    }

    for (final stray in strays) {
      final uuid = stray['uuid'] as String;

      for (final table in ['tasks', 'parked_groups', 'journal_entries']) {
        await db.update(
          table,
          {'workspace_uuid': defaultWorkspaceUuid, 'updated_at': now, 'dirty': 1},
          where: 'workspace_uuid = ?',
          whereArgs: [uuid],
        );
      }

      // A workspace's calendar carries the workspace's own uuid
      // (Calendar.forWorkspace), so a duplicate workspace brought a duplicate
      // calendar with it. Its events move to the canonical calendar; the empty
      // calendar goes the way of its workspace.
      await db.update(
        'calendar_events',
        {'calendar_uuid': defaultWorkspaceUuid, 'updated_at': now, 'dirty': 1},
        where: 'calendar_uuid = ?',
        whereArgs: [uuid],
      );
      await db.update(
        'calendars',
        {'deleted_at': now, 'updated_at': now, 'dirty': 1},
        where: 'uuid = ? AND deleted_at IS NULL',
        whereArgs: [uuid],
      );

      await db.update(
        'workspaces',
        {'deleted_at': now, 'updated_at': now, 'dirty': 1},
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
    }
  }

  static const _calendarsTable = '''
      CREATE TABLE calendars (
        uuid           TEXT PRIMARY KEY,
        workspace_uuid TEXT,
        name           TEXT NOT NULL DEFAULT '',
        color          TEXT NOT NULL DEFAULT '#6c8cff',
        notify_minutes INTEGER,
        sort_order     INTEGER NOT NULL DEFAULT 0,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''';

  static const _calendarEventsTable = '''
      CREATE TABLE calendar_events (
        uuid           TEXT PRIMARY KEY,
        calendar_uuid  TEXT NOT NULL,
        title          TEXT NOT NULL,
        description    TEXT NOT NULL DEFAULT '',
        start_at       TEXT NOT NULL,
        end_at         TEXT NOT NULL,
        notify_minutes INTEGER,
        recur          TEXT,
        all_day        INTEGER NOT NULL DEFAULT 0,
        feed_uuid      TEXT,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''';

  /// Every column but the key and the stamps nullable, for the reason
  /// `tasks.recur_from` is - see [CalendarFeed.fromMap].
  static const _calendarFeedsTable = '''
      CREATE TABLE calendar_feeds (
        uuid          TEXT PRIMARY KEY,
        calendar_uuid TEXT,
        name          TEXT,
        url           TEXT,
        alerts        INTEGER,
        created_at    TEXT,
        updated_at    TEXT NOT NULL,
        deleted_at    TEXT,
        dirty         INTEGER NOT NULL DEFAULT 1
      )''';

  /// The shopping list (v17). Nullable for the reason [_calendarFeedsTable]
  /// is.
  static const _listsTable = '''
      CREATE TABLE lists (
        uuid        TEXT PRIMARY KEY,
        name        TEXT,
        archived_at TEXT,
        created_at  TEXT,
        updated_at  TEXT NOT NULL,
        deleted_at  TEXT,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''';

  static const _listItemsTable = '''
      CREATE TABLE list_items (
        uuid       TEXT PRIMARY KEY,
        list_uuid  TEXT,
        text       TEXT,
        checked_at TEXT,
        sort_order INTEGER,
        created_at TEXT,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        dirty      INTEGER NOT NULL DEFAULT 1
      )''';

  static const _listItemsIndex =
      'CREATE INDEX idx_list_items_list ON list_items (list_uuid)';

  /// Collections (v18): a workspace's tables of entries with fields you define
  /// first. Nullable for the reason [_calendarFeedsTable] is.
  static const _collectionsTable = '''
      CREATE TABLE collections (
        uuid           TEXT PRIMARY KEY,
        workspace_uuid TEXT,
        name           TEXT,
        sort_order     INTEGER,
        created_at     TEXT,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''';

  /// One row per field rather than a JSON column on the collection, so a
  /// rename on one device and a new field on another both survive a merge.
  /// `options` is unused until choice fields exist; it is here so adding them
  /// is not another protocol bump.
  static const _collectionFieldsTable = '''
      CREATE TABLE collection_fields (
        uuid            TEXT PRIMARY KEY,
        collection_uuid TEXT,
        name            TEXT,
        kind            TEXT,
        options         TEXT,
        sort_order      INTEGER,
        created_at      TEXT,
        updated_at      TEXT NOT NULL,
        deleted_at      TEXT,
        dirty           INTEGER NOT NULL DEFAULT 1
      )''';

  /// `data` is a JSON object keyed by field uuid. Not `values`, which is an
  /// SQL keyword.
  static const _collectionEntriesTable = '''
      CREATE TABLE collection_entries (
        uuid            TEXT PRIMARY KEY,
        collection_uuid TEXT,
        data            TEXT,
        sort_order      INTEGER,
        created_at      TEXT,
        updated_at      TEXT NOT NULL,
        deleted_at      TEXT,
        dirty           INTEGER NOT NULL DEFAULT 1
      )''';

  static const _collectionsWorkspaceIndex =
      'CREATE INDEX idx_collections_workspace ON collections (workspace_uuid)';
  static const _collectionFieldsIndex =
      'CREATE INDEX idx_collection_fields_collection '
      'ON collection_fields (collection_uuid)';
  static const _collectionEntriesIndex =
      'CREATE INDEX idx_collection_entries_collection '
      'ON collection_entries (collection_uuid)';

  /// A refresh asks for every row one feed wrote.
  static const _eventsFeedIndex =
      'CREATE INDEX idx_events_feed ON calendar_events (feed_uuid)';

  /// The v8 shape, kept verbatim for the upgrade path only. A database coming
  /// from v7 or earlier creates the table here and then has `recur` added by
  /// the from < 13 step; building the current shape in both places is how you
  /// get "duplicate column name" halfway through a migration.
  static const _calendarEventsTableV8 = '''
      CREATE TABLE calendar_events (
        uuid           TEXT PRIMARY KEY,
        calendar_uuid  TEXT NOT NULL,
        title          TEXT NOT NULL,
        description    TEXT NOT NULL DEFAULT '',
        start_at       TEXT NOT NULL,
        end_at         TEXT NOT NULL,
        notify_minutes INTEGER,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''';

  static const _calendarsWsIndex =
      'CREATE INDEX idx_calendars_ws ON calendars (workspace_uuid)';
  static const _eventsCalendarIndex =
      'CREATE INDEX idx_events_cal ON calendar_events (calendar_uuid)';

  /// The week and day views both ask for one window of time across every
  /// visible calendar, so the range scan is the query that has to be fast.
  static const _eventsStartIndex =
      'CREATE INDEX idx_events_start ON calendar_events (start_at)';

  /// Bytes a row names by digest - a voice note's audio. Device-local and
  /// never synced as a table: what was recorded here waits with `uploaded` 0
  /// until a sync puts it on the server, and what was fetched from there is
  /// a cache, trimmed oldest-used first ([trimBlobs]).
  static const _blobsTable = '''
      CREATE TABLE blobs (
        sha256   TEXT PRIMARY KEY,
        type     TEXT NOT NULL,
        size     INTEGER NOT NULL,
        data     BLOB NOT NULL,
        uploaded INTEGER NOT NULL DEFAULT 0,
        used_at  TEXT NOT NULL
      )''';

  static const _attachmentsEventIndex =
      'CREATE INDEX idx_attachments_event ON attachments (event_uuid)';

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

  /// The v4 attachments table, kept verbatim for the upgrade path from a
  /// database that predated calendar events owning attachments. `event_uuid` is
  /// added to it by the from < 8 migration; a fresh database gets
  /// [_attachmentsTable] with the column already in place, so the create and
  /// that ALTER never collide.
  static const _attachmentsTableV4 = '''
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

  /// `task_uuid` keeps its NOT NULL and gains a default: an attachment on a
  /// calendar event has no task, and the empty string says so without making
  /// every existing read handle a null.
  static const _attachmentsTable = '''
      CREATE TABLE attachments (
        uuid       TEXT PRIMARY KEY,
        task_uuid  TEXT NOT NULL DEFAULT '',
        event_uuid TEXT,
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

  /// The session view asks "what is planned into this block" every poll, which
  /// is the one read here that runs on a timer.
  static const _tasksEventIndex =
      'CREATE INDEX idx_tasks_event ON tasks (event_uuid)';

  /// The recurrence sweep runs on the same timer and asks for every row that
  /// carries a rule - a small fraction of the table, and one the planner can
  /// only find cheaply with an index on the column being tested.
  static const _tasksRecurIndex =
      'CREATE INDEX idx_tasks_recur ON tasks (recur)';

  static Future<void> _create(
    Database db,
    int version, {
    bool seedWorkspace = true,
  }) async {
    await db.execute('''
      CREATE TABLE workspaces (
        uuid       TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        color      TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        shortcuts  TEXT,
        parent_uuid TEXT,
        archived_at TEXT,
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
        recur          TEXT,
        -- Nullable, unlike Task.recurFrom, which is not. applyRemote inserts a
        -- server's row verbatim, and a server row written by a device that
        -- predates this column carries recur_from: null - which a NOT NULL
        -- would turn into a constraint failure that aborts the whole merge
        -- transaction, so one old peer would stop every row arriving. Null is
        -- read back as 'schedule' by Task.fromMap, which is what such a row
        -- means, so there is still no third state in the model.
        recur_from     TEXT,
        recur_lead     INTEGER,
        recur_text     TEXT,
        recur_notes    TEXT,
        group_uuid     TEXT,
        event_uuid     TEXT,
        notes          TEXT NOT NULL DEFAULT '',
        priority       INTEGER NOT NULL DEFAULT 0,
        audio          TEXT,
        audio_ms       INTEGER,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''');

    await db.execute(_parkedGroupsTable);
    await db.execute(_attachmentsTable);
    await db.execute(_journalTable);
    await db.execute(_calendarsTable);
    await db.execute(_calendarEventsTable);
    await db.execute(_calendarFeedsTable);
    await db.execute(_listsTable);
    await db.execute(_listItemsTable);
    await db.execute(_collectionsTable);
    await db.execute(_collectionFieldsTable);
    await db.execute(_collectionEntriesTable);

    await db.execute('''
      CREATE TABLE side_thoughts (
        uuid        TEXT PRIMARY KEY,
        text        TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        resolved_at TEXT,
        audio       TEXT,
        audio_ms    INTEGER,
        remind_at   TEXT,
        updated_at  TEXT NOT NULL,
        deleted_at  TEXT,
        dirty       INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute(_blobsTable);

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
    await db.execute(_tasksEventIndex);
    await db.execute(_tasksRecurIndex);
    await db.execute(_attachmentsIndex);
    await db.execute(_attachmentsEventIndex);
    await db.execute(_journalIndex);
    await db.execute(_calendarsWsIndex);
    await db.execute(_eventsCalendarIndex);
    await db.execute(_eventsStartIndex);
    await db.execute(_eventsFeedIndex);
    await db.execute(_listItemsIndex);
    await db.execute(_collectionsWorkspaceIndex);
    await db.execute(_collectionFieldsIndex);
    await db.execute(_collectionEntriesIndex);

    // A first workspace, for the test fixtures; see [open].
    if (!seedWorkspace) return;
    final now = nowStamp();
    await db.insert('workspaces', {
      'uuid': defaultWorkspaceUuid,
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

  /// A `tasks` predicate: not in an archived project. An archived project is
  /// put away whole, so nothing in it reminds, holds focus, spawns its next
  /// occurrence or turns up in a session - and restoring it brings all of
  /// that back with nothing to re-arm, since none of it was touched.
  static const _notArchived = 'workspace_uuid NOT IN '
      '(SELECT uuid FROM workspaces WHERE archived_at IS NOT NULL)';

  /// Every live workspace, projects and archived projects included -
  /// `AppState` splits them.
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

  /// Every shelf's title by uuid, in every workspace. For prefixing a task
  /// that leaves its shelf - which may be another workspace's, through the
  /// move picker - and small enough that one query beats a lookup per task.
  Future<Map<String, String>> groupTitles() async {
    final rows = await _db.query('parked_groups', columns: ['uuid', 'title']);
    return {for (final r in rows) r['uuid'] as String: r['title'] as String};
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
            'AND deleted_at IS NULL AND group_uuid IS NULL AND $_notArchived',
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
            'AND deleted_at IS NULL AND group_uuid IS NULL AND $_notArchived',
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

  /// Thoughts with a reminder, still in the pile: [_armed]'s twin, with the
  /// comparison in Dart for the same reason.
  Future<List<SideThought>> _armedThoughts() async {
    final rows = await _db.query('side_thoughts',
        where: 'remind_at IS NOT NULL AND resolved_at IS NULL '
            'AND deleted_at IS NULL',
        orderBy: 'remind_at');
    return rows.map(SideThought.fromMap).toList();
  }

  Future<List<SideThought>> dueThoughtReminders([DateTime? now]) async =>
      (await _armedThoughts()).where((t) => t.isDue(now)).toList();

  Future<List<SideThought>> pendingThoughtReminders([DateTime? now]) async =>
      (await _armedThoughts()).where((t) => !t.isDue(now)).toList();

  Future<Task?> taskByUuid(String uuid) async {
    final rows = await _db
        .query('tasks', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  /// How far back a completed recurring task is still worth asking about.
  ///
  /// Every occurrence carries the rule, so *every* row a series has ever
  /// produced is nominally a seed for the next one - which over a couple of
  /// years of a daily task is a thousand rows to walk on a 20-second timer, for
  /// an answer the newest row already gives. A series whose latest row is open
  /// is always found, and one whose latest row was ticked has produced its
  /// successor within the lead of the following occurrence; the only thing this
  /// window loses is a series last touched over a year ago on a device that has
  /// been off ever since, which is a series that has stopped.
  static const recurringSeedWindow = Duration(days: 400);

  /// Candidate rows for the recurrence sweep: everything carrying a rule that
  /// could still owe an occurrence.
  ///
  /// Tombstones are excluded, and that is how a series is stopped from a row
  /// that is already in History - deleting it takes the seed away.
  Future<List<Task>> recurringSeeds([DateTime? now]) async {
    final since =
        (now ?? DateTime.now()).subtract(recurringSeedWindow);
    final rows = await _db.query(
      'tasks',
      where: 'recur IS NOT NULL AND deleted_at IS NULL AND $_notArchived '
          'AND (completed_at IS NULL OR completed_at >= ?)',
      whereArgs: [stampOf(since)],
    );
    return rows.map(Task.fromMap).toList();
  }

  /// Which of [uuids] the table already holds, **tombstones included**.
  ///
  /// One question rather than one per candidate: the sweep asks about every
  /// series at once, and a deleted occurrence has to read as "exists" or the
  /// next sweep would put it straight back.
  Future<Set<String>> existingTaskUuids(List<String> uuids) async {
    if (uuids.isEmpty) return {};
    final marks = List.filled(uuids.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT uuid FROM tasks WHERE uuid IN ($marks)',
      uuids,
    );
    return {for (final r in rows) r['uuid'] as String};
  }

  Future<List<Attachment>> attachmentsFor(String taskUuid) async {
    final rows = await _db.query('attachments',
        // Event rows carry an empty task_uuid, so without this a caller that
        // ever passed '' would be handed every attachment on the calendar.
        where: 'task_uuid = ? AND event_uuid IS NULL AND deleted_at IS NULL',
        whereArgs: [taskUuid],
        orderBy: 'created_at');
    return rows.map(Attachment.fromMap).toList();
  }

  Future<List<Attachment>> eventAttachments(String eventUuid) async {
    final rows = await _db.query('attachments',
        where: 'event_uuid = ? AND deleted_at IS NULL',
        whereArgs: [eventUuid],
        orderBy: 'created_at');
    return rows.map(Attachment.fromMap).toList();
  }

  /// Which events have at least one attachment, for the paperclip on the blob.
  ///
  /// A set rather than counts: the grid draws one icon regardless of how many,
  /// and at the size an event is drawn there is no room for a number.
  Future<Set<String>> eventsWithAttachments() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT event_uuid FROM attachments '
      'WHERE event_uuid IS NOT NULL AND deleted_at IS NULL',
    );
    return {for (final r in rows) r['event_uuid']! as String};
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

  // -------------------------------------------------------------- calendars

  Future<List<Calendar>> calendars() async {
    final rows = await _db.query('calendars',
        where: 'deleted_at IS NULL', orderBy: 'sort_order, created_at');
    return rows.map(Calendar.fromMap).toList();
  }

  /// Events overlapping [from, to).
  ///
  /// Overlap, not containment: an event that started yesterday and ends
  /// tomorrow belongs on today's grid, and a query keyed only on `start_at`
  /// would miss exactly the multi-day events the spanning band exists for.
  ///
  /// Both bounds are compared as stored UTC strings, which is a valid ordering
  /// here because [reminderStamp] normalises every stamp to UTC before it is
  /// written - unlike the local-offset stamps [compareStamps] has to parse.
  /// A repeating row is fetched whenever its *first* occurrence begins before
  /// the window ends, and is then expanded in Dart. It cannot be filtered on
  /// `end_at` the way a one-off is: a series has no end, so the only thing the
  /// stored end says is how long one occurrence lasts.
  Future<List<CalendarEvent>> eventsBetween(DateTime from, DateTime to) async {
    final toStamp = reminderStamp(to);
    final rows = await _db.query(
      'calendar_events',
      where: 'deleted_at IS NULL AND ('
          '(recur IS NULL AND start_at < ? AND end_at > ?) OR '
          '(recur IS NOT NULL AND start_at < ?))',
      whereArgs: [toStamp, reminderStamp(from), toStamp],
      orderBy: 'start_at',
    );
    return _expand(rows, from, to);
  }

  /// Every event that has not finished yet, for the notification schedule.
  ///
  /// A series contributes exactly **one** instant - its next occurrence. The
  /// schedule is rewritten wholesale on every change, so handing the OS a year
  /// of a daily block would be a year of alarms to cancel each time anything
  /// is touched, to say nothing of the platform limits on how many an app may
  /// hold.
  Future<List<CalendarEvent>> upcomingEvents([DateTime? now]) async {
    final at = now ?? DateTime.now();
    final rows = await _db.query(
      'calendar_events',
      where: 'deleted_at IS NULL AND (recur IS NOT NULL OR end_at > ?)',
      whereArgs: [reminderStamp(at)],
      orderBy: 'start_at',
    );
    final out = <CalendarEvent>[];
    for (final row in rows.map(CalendarEvent.fromMap)) {
      final next = row.nextOccurrence(at);
      if (next != null) out.add(next);
    }
    out.sort((a, b) => a.startAt.compareTo(b.startAt));
    return out;
  }

  /// Expand the stored rows into the occurrences that overlap `[from, to)`,
  /// back in start order. A one-off yields itself, so this is the one path
  /// every calendar read goes through and there is no second answer to "what
  /// is on screen".
  static List<CalendarEvent> _expand(
    List<Map<String, Object?>> rows,
    DateTime from,
    DateTime to,
  ) {
    final out = <CalendarEvent>[];
    for (final row in rows.map(CalendarEvent.fromMap)) {
      out.addAll(row.occurrencesBetween(from, to));
    }
    out.sort((a, b) => a.startAt.compareTo(b.startAt));
    return out;
  }

  /// The events covering this instant - the block (or blocks) you are in.
  ///
  /// Half-open at the start and closed at the end for the same reason the grid
  /// is: an event ending at 11:00 is over at 11:00, and one starting then has
  /// begun. Overlaps are not resolved here - two events really can be running
  /// at once, and picking one of them for the user would be guessing.
  Future<List<CalendarEvent>> liveEvents([DateTime? now]) async {
    final at = now ?? DateTime.now();
    final stamp = reminderStamp(at);
    final rows = await _db.query(
      'calendar_events',
      where: 'deleted_at IS NULL AND ('
          '(recur IS NULL AND start_at <= ? AND end_at > ?) OR '
          '(recur IS NOT NULL AND start_at <= ?))',
      whereArgs: [stamp, stamp, stamp],
      orderBy: 'start_at',
    );

    final out = <CalendarEvent>[];
    for (final row in rows.map(CalendarEvent.fromMap)) {
      // The window starts one occurrence-length back, because the occurrence
      // covering this instant is one that *began* before it. Overlap is then
      // narrowed to the same half-open test the SQL uses for a one-off.
      for (final e in row.occurrencesBetween(
        at.subtract(row.duration),
        at.add(const Duration(milliseconds: 1)),
      )) {
        if (!e.start.isAfter(at) && e.end.isAfter(at)) out.add(e);
      }
    }
    out.sort((a, b) => a.startAt.compareTo(b.startAt));
    return out;
  }

  /// What is still to be done in one block.
  ///
  /// Parked tasks are excluded, exactly as they are from [activeTasks] and the
  /// reminder sweep: shelving something says "not now", and a session list is
  /// the most emphatic "now" in the app. The `event_uuid` is kept either way,
  /// so unparking puts it back in its block.
  Future<List<Task>> tasksForEvent(String eventUuid) async {
    final rows = await _db.query('tasks',
        where: 'event_uuid = ? AND completed_at IS NULL '
            'AND deleted_at IS NULL AND group_uuid IS NULL AND $_notArchived',
        whereArgs: [eventUuid],
        orderBy: 'sort_order, created_at');
    return rows.map(Task.fromMap).toList();
  }

  /// Every live task pointing at an event, completed and parked ones included.
  /// Used when the event goes away, which has to release all of them - a task
  /// pointing at a deleted block would be unreachable from any session.
  Future<List<Task>> allTasksForEvent(String eventUuid) async {
    final rows = await _db.query('tasks',
        where: 'event_uuid = ? AND deleted_at IS NULL',
        whereArgs: [eventUuid]);
    return rows.map(Task.fromMap).toList();
  }

  /// How many open tasks each event has, keyed by event uuid; events with none
  /// are absent. One query for the whole grid, like [attachmentCounts].
  Future<Map<String, int>> eventTaskCounts() async {
    final rows = await _db.rawQuery(
      'SELECT event_uuid, COUNT(*) AS n FROM tasks '
      'WHERE event_uuid IS NOT NULL AND completed_at IS NULL '
      'AND deleted_at IS NULL AND group_uuid IS NULL '
      'GROUP BY event_uuid',
    );
    return {
      for (final r in rows)
        r['event_uuid']! as String: (r['n'] as num).toInt(),
    };
  }

  /// Every live event on one calendar, for cascading a delete.
  Future<List<CalendarEvent>> eventsOnCalendar(String calendarUuid) async {
    final rows = await _db.query('calendar_events',
        where: 'calendar_uuid = ? AND deleted_at IS NULL',
        whereArgs: [calendarUuid],
        orderBy: 'start_at');
    return rows.map(CalendarEvent.fromMap).toList();
  }

  Future<CalendarEvent?> eventByUuid(String uuid) async {
    final rows = await _db
        .query('calendar_events', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return null;
    return CalendarEvent.fromMap(rows.first);
  }

  Future<List<CalendarFeed>> calendarFeeds() async {
    final rows = await _db.query('calendar_feeds',
        where: 'deleted_at IS NULL', orderBy: 'created_at');
    return rows.map(CalendarFeed.fromMap).toList();
  }

  /// Lists not yet finished, newest first. The first is the current one; any
  /// more are what two devices each starting a list offline leaves behind.
  Future<List<ShoppingList>> openLists() async {
    final rows = await _db.query('lists',
        where: 'archived_at IS NULL AND deleted_at IS NULL',
        orderBy: 'created_at DESC, uuid');
    return rows.map(ShoppingList.fromMap).toList();
  }

  /// Finished lists, most recently finished first.
  Future<List<ShoppingList>> archivedLists() async {
    final rows = await _db.query('lists',
        where: 'archived_at IS NOT NULL AND deleted_at IS NULL',
        orderBy: 'archived_at DESC');
    return rows.map(ShoppingList.fromMap).toList();
  }

  /// A list's live items, in the order they were put in.
  Future<List<ListItem>> listItems(String listUuid) async {
    final rows = await _db.query('list_items',
        where: 'list_uuid = ? AND deleted_at IS NULL',
        whereArgs: [listUuid],
        orderBy: 'sort_order, created_at');
    return rows.map(ListItem.fromMap).toList();
  }

  /// Live items per list, for the archive's counts.
  Future<Map<String, int>> listItemCounts() async {
    final rows = await _db.rawQuery(
        'SELECT list_uuid, COUNT(*) AS n FROM list_items '
        'WHERE deleted_at IS NULL GROUP BY list_uuid');
    return {
      for (final r in rows)
        if (r['list_uuid'] != null)
          r['list_uuid']! as String: (r['n']! as num).toInt(),
    };
  }

  /// A workspace's collections, in their order.
  Future<List<Collection>> collections(String workspaceUuid) async {
    final rows = await _db.query('collections',
        where: 'workspace_uuid = ? AND deleted_at IS NULL',
        whereArgs: [workspaceUuid],
        orderBy: 'sort_order, created_at');
    return rows.map(Collection.fromMap).toList();
  }

  /// The live fields of every live collection in a workspace, in field order.
  /// One query for the whole view rather than one per collection: the list of
  /// collections names each one's fields.
  Future<List<CollectionField>> collectionFields(String workspaceUuid) async {
    final rows = await _db.rawQuery('''
      SELECT f.* FROM collection_fields f
        JOIN collections c ON c.uuid = f.collection_uuid
       WHERE c.workspace_uuid = ? AND c.deleted_at IS NULL
         AND f.deleted_at IS NULL
       ORDER BY f.sort_order, f.created_at''', [workspaceUuid]);
    return rows.map(CollectionField.fromMap).toList();
  }

  /// The live entries of every live collection in a workspace, newest first.
  /// A workspace's collections are small enough to hold whole, which is what
  /// lets search and sort be done in memory.
  Future<List<CollectionEntry>> collectionEntries(String workspaceUuid) async {
    final rows = await _db.rawQuery('''
      SELECT e.* FROM collection_entries e
        JOIN collections c ON c.uuid = e.collection_uuid
       WHERE c.workspace_uuid = ? AND c.deleted_at IS NULL
         AND e.deleted_at IS NULL
       ORDER BY e.created_at DESC, e.uuid''', [workspaceUuid]);
    return rows.map(CollectionEntry.fromMap).toList();
  }

  /// Every live event one feed wrote, for unsubscribing.
  Future<List<CalendarEvent>> feedEvents(String feedUuid) async {
    final rows = await _db.query('calendar_events',
        where: 'feed_uuid = ? AND deleted_at IS NULL', whereArgs: [feedUuid]);
    return rows.map(CalendarEvent.fromMap).toList();
  }

  /// Make one feed's events in `[from, to)` exactly [rows], writing only what
  /// differs.
  ///
  /// **Only what differs** is the property everything else rests on. Every
  /// device holding the subscription refreshes it, and the rows have derived
  /// ids, so the second device to fetch an unchanged feed computes rows it
  /// already has from the first one's sync - and must write nothing, or each
  /// refresh would push the whole calendar back to the server and wake every
  /// other device to pull it.
  ///
  /// A row outside the window is left alone, whatever the feed now says.
  /// Behind it, that is history: the feed is only expanded so far back, and an
  /// old meeting falling out of the window is not a meeting that was
  /// cancelled. Ahead of it, another device whose clock reads a little later
  /// may have written an occurrence this one has not reached yet; removing it
  /// would have the two of them taking turns.
  Future<({int added, int changed, int removed})> applyFeedRows(
    String feedUuid,
    List<CalendarEvent> rows, {
    required DateTime from,
    required DateTime to,
  }) async {
    var added = 0, changed = 0, removed = 0;
    await _db.transaction((txn) async {
      final existing = {
        for (final r in await txn.query('calendar_events',
            where: 'feed_uuid = ?', whereArgs: [feedUuid]))
          r['uuid']! as String: r,
      };
      final stamp = nowStamp();
      final wanted = <String>{};

      for (final row in rows) {
        wanted.add(row.uuid);
        final map = row.toMap();
        final old = existing[row.uuid];
        if (old != null && old['deleted_at'] == null && _sameEvent(old, map)) {
          continue;
        }
        await txn.insert(
          'calendar_events',
          {
            ...map,
            'created_at': old?['created_at'] ?? stamp,
            'updated_at': stamp,
            'deleted_at': null,
            'dirty': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (old == null || old['deleted_at'] != null) {
          added++;
        } else {
          changed++;
        }
      }

      final fromStamp = reminderStamp(from);
      final toStamp = reminderStamp(to);
      for (final old in existing.values) {
        if (old['deleted_at'] != null || wanted.contains(old['uuid'])) continue;
        final end = old['end_at']! as String;
        final start = old['start_at']! as String;
        if (end.compareTo(fromStamp) <= 0 || start.compareTo(toStamp) >= 0) {
          continue;
        }
        await txn.update(
          'calendar_events',
          {'deleted_at': stamp, 'updated_at': stamp, 'dirty': 1},
          where: 'uuid = ?',
          whereArgs: [old['uuid']],
        );
        removed++;
      }
    });
    return (added: added, changed: changed, removed: removed);
  }

  /// The columns a feed decides. The stamps are not among them - they say when
  /// a row was written, and two devices write the same row at different times.
  static const _feedColumns = [
    'calendar_uuid',
    'title',
    'description',
    'start_at',
    'end_at',
    'notify_minutes',
    'all_day',
    'recur',
    'feed_uuid',
  ];

  static bool _sameEvent(Map<String, Object?> a, Map<String, Object?> b) {
    for (final c in _feedColumns) {
      if ('${a[c]}' != '${b[c]}') return false;
    }
    return true;
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

  // ------------------------------------------------------------------ blobs

  /// Keep [data] under [sha256]. [uploaded] false queues it for the server;
  /// true is a copy of what the server already has.
  Future<void> putBlob(
    String sha256,
    String type,
    Uint8List data, {
    bool uploaded = false,
  }) async {
    await _db.insert('blobs', {
      'sha256': sha256,
      'type': type,
      'size': data.length,
      'data': data,
      'uploaded': uploaded ? 1 : 0,
      'used_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// The bytes and their type, or null when this device has never had them.
  Future<({String type, Uint8List data})?> blob(String sha256) async {
    final rows = await _db.query('blobs',
        columns: ['type', 'data'], where: 'sha256 = ?', whereArgs: [sha256]);
    if (rows.isEmpty) return null;
    await _db.update(
        'blobs', {'used_at': DateTime.now().toUtc().toIso8601String()},
        where: 'sha256 = ?', whereArgs: [sha256]);
    final data = rows.first['data'];
    return (
      type: rows.first['type']! as String,
      data: data is Uint8List ? data : Uint8List.fromList(data! as List<int>),
    );
  }

  /// The digests still waiting to go to the server.
  Future<List<String>> pendingBlobs() async {
    final rows = await _db.query('blobs',
        columns: ['sha256'], where: 'uploaded = 0', orderBy: 'used_at');
    return [for (final r in rows) r['sha256']! as String];
  }

  Future<void> markBlobUploaded(String sha256) => _db.update(
      'blobs', {'uploaded': 1},
      where: 'sha256 = ?', whereArgs: [sha256]);

  /// Drop the least recently used copies until what is kept fits in
  /// [maxBytes]. Never one still waiting to be uploaded: that is the only
  /// copy there is.
  Future<void> trimBlobs(int maxBytes) async {
    final rows = await _db.query('blobs',
        columns: ['sha256', 'size'],
        where: 'uploaded = 1',
        orderBy: 'used_at DESC');
    var kept = 0;
    final drop = <String>[];
    for (final r in rows) {
      kept += (r['size']! as num).toInt();
      if (kept > maxBytes) drop.add(r['sha256']! as String);
    }
    for (final sha in drop) {
      await _db.delete('blobs', where: 'sha256 = ?', whereArgs: [sha]);
    }
  }
  Future<void> putGroup(ParkedGroup g) => put('parked_groups', g);
  Future<void> putAttachment(Attachment a) => put('attachments', a);
  Future<void> putJournal(JournalEntry e) => put('journal_entries', e);
  Future<void> putCalendar(Calendar c) => put('calendars', c);
  Future<void> putEvent(CalendarEvent e) => put('calendar_events', e);
  Future<void> putFeed(CalendarFeed f) => put('calendar_feeds', f);
  Future<void> putList(ShoppingList l) => put('lists', l);
  Future<void> putListItem(ListItem i) => put('list_items', i);
  Future<void> putCollection(Collection c) => put('collections', c);
  Future<void> putCollectionField(CollectionField f) =>
      put('collection_fields', f);
  Future<void> putCollectionEntry(CollectionEntry e) =>
      put('collection_entries', e);

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
  /// Writes a list's order. A uuid may name a task or a **project** on that
  /// list: they are rows of one list and share one order, so each uuid is
  /// tried against both tables and matches exactly one of them.
  Future<void> reorderTasks(List<String> uuids) async {
    final stamp = nowStamp();
    await _db.transaction((txn) async {
      for (var i = 0; i < uuids.length; i++) {
        final row = {'sort_order': i, 'updated_at': stamp, 'dirty': 1};
        final n = await txn.update('tasks', row,
            where: 'uuid = ?', whereArgs: [uuids[i]]);
        if (n == 0) {
          await txn.update('workspaces', row,
              where: 'uuid = ? AND parent_uuid IS NOT NULL',
              whereArgs: [uuids[i]]);
        }
      }
    });
  }

  /// Next sort_order for a new task, so it appends rather than jumping to the
  /// top of a manually ordered list. The list's projects count too: they are
  /// rows of the same list and share its order.
  Future<int> nextSortOrder(String workspaceUuid) async {
    final rows = await _db.rawQuery(
      'SELECT MAX(m) AS m FROM ('
      'SELECT MAX(sort_order) AS m FROM tasks WHERE workspace_uuid = ? '
      'UNION ALL '
      'SELECT MAX(sort_order) AS m FROM workspaces WHERE parent_uuid = ?)',
      [workspaceUuid, workspaceUuid],
    );
    return ((rows.first['m'] as num?)?.toInt() ?? -1) + 1;
  }

  /// How many open tasks are on each project's list, keyed by project uuid -
  /// the count its row in the parent's list shows. Shelved tasks are not on
  /// the list, so they are not counted.
  Future<Map<String, int>> projectOpenCounts() async {
    final rows = await _db.rawQuery(
      'SELECT t.workspace_uuid AS w, COUNT(*) AS n FROM tasks t '
      'JOIN workspaces p ON p.uuid = t.workspace_uuid '
      'WHERE p.parent_uuid IS NOT NULL AND t.completed_at IS NULL '
      'AND t.deleted_at IS NULL AND t.group_uuid IS NULL '
      'GROUP BY t.workspace_uuid',
    );
    return {for (final r in rows) r['w'] as String: (r['n'] as num).toInt()};
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

  /// Re-arm every row for upload, and report how many that was.
  ///
  /// `dirty` records that *a* server accepted a row, never *which* one. Point
  /// the app at a rebuilt database, a restored backup or a different account
  /// and every clean row is simultaneously "already sent" here and absent
  /// there - so nothing ever pushes it again and the two sides quietly stay
  /// different forever. This is the only way back out of that state.
  ///
  /// It is safe to call when it was not needed. The merge is last-write-wins
  /// on `updated_at`, so a row the server holds a newer copy of is not
  /// clobbered, and a row it holds at the same stamp is not even rewritten -
  /// ties go to the incumbent (`mergeRow` in server/db.js), which means no new
  /// `seq` and nothing re-broadcast to the other devices. A needless re-arm
  /// therefore costs one larger request and changes nothing.
  Future<int> markAllDirty() async {
    var total = 0;
    await _db.transaction((txn) async {
      for (final table in _tables) {
        // Tombstones included: a delete that never reached this server has to
        // go out for exactly the same reason a live row does.
        total += await txn.rawUpdate('UPDATE $table SET dirty = 1');
      }
    });
    return total;
  }

  /// How many local rows are still waiting to reach the server.
  ///
  /// Writes never block on the network, so a server that is off is
  /// indistinguishable from one that is up by looking at the app alone. This
  /// count is what lets the UI say "your work is queued" rather than leaving
  /// the user to guess.
  /// Whether this database has ever held a task, done or deleted ones
  /// included: what tells a device that has been in use from a fresh install
  /// when there is no other record to go by.
  Future<bool> hasAnyTask() async {
    final rows = await _db.rawQuery('SELECT 1 FROM tasks LIMIT 1');
    return rows.isNotEmpty;
  }

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

          // A column the server did not send is one it does not have - a pull
          // is `SELECT *`, so a column it knows always comes back, null or not.
          // Keep ours rather than letting the replace reset it to its default:
          // a server one release behind would otherwise erase whatever the
          // newer column holds every time a row comes back from it (a feed's
          // events would stop being read-only, and the next refresh would
          // rewrite every one of them, every time).
          //
          // And the other way round: a column *we* do not have is dropped. A
          // newer server should not send one (it withholds what a client's
          // protocol does not cover), but the insert failing on it would abort
          // this whole merge, so one stray column would stop every row moving.
          final known = await _columnsOf(txn, table);
          final row = <String, Object?>{
            if (existing.isNotEmpty) ...existing.first,
            ...remote,
          }
            ..remove('seq')
            ..removeWhere((k, _) => !known.contains(k))
            ..['dirty'] = 0;
          await txn.insert(table, row,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  final _columns = <String, Set<String>>{};

  Future<Set<String>> _columnsOf(DatabaseExecutor db, String table) async =>
      _columns[table] ??= {
        for (final c in await db.rawQuery('PRAGMA table_info($table)'))
          c['name']! as String,
      };

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
