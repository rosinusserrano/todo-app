// Sync server storage.
//
// The schema deliberately mirrors the client's local SQLite, with three
// additions that make rows syncable:
//
//   uuid       - client-generated primary key. Replaces the old AUTOINCREMENT
//                integer ids, which collided the moment two devices created a
//                row while offline.
//   updated_at - RFC 3339, set by whichever device last touched the row. This
//                is the *conflict* signal: merges are last-write-wins on it.
//   deleted_at - tombstone. Rows are never hard-deleted, because a peer cannot
//                tell "deleted elsewhere" from "not yet seen" if the row just
//                vanishes.
//
// `seq` is separate from `updated_at` on purpose. It is a server-assigned
// monotonic counter used only as the pull cursor. Using wall-clock time as a
// cursor loses writes whenever a device's clock is behind the server's, which
// is exactly the situation a phone roaming between timezones creates.

import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export function openDb(path) {
  mkdirSync(dirname(path), { recursive: true });
  const db = new Database(path);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  init(db);
  return db;
}

function init(db) {
  // Server-assigned cursor. A single row holding the last handed-out seq.
  db.exec(`
    CREATE TABLE IF NOT EXISTS meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
    INSERT OR IGNORE INTO meta (key, value) VALUES ('seq', '0');

    CREATE TABLE IF NOT EXISTS workspaces (
      uuid       TEXT NOT NULL,
      user_id    TEXT NOT NULL,
      name       TEXT NOT NULL,
      color      TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      seq        INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );

    CREATE TABLE IF NOT EXISTS tasks (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
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
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );

    CREATE TABLE IF NOT EXISTS parked_groups (
      uuid              TEXT NOT NULL,
      user_id           TEXT NOT NULL,
      workspace_uuid    TEXT NOT NULL,
      title             TEXT NOT NULL,
      -- Nullable, unlike the client's column: the merge writes whatever the
      -- push carried, and a NOT NULL here would turn one malformed row into a
      -- rejected sync for the whole device.
      review_every_days INTEGER,
      last_reviewed_at  TEXT,
      sort_order        INTEGER NOT NULL DEFAULT 0,
      created_at        TEXT NOT NULL,
      updated_at        TEXT NOT NULL,
      deleted_at        TEXT,
      seq               INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );

    -- Attachment *metadata* only. The bytes are not synced: this protocol is
    -- one JSON round trip of rows, and pushing documents through it would make
    -- every sync wait on the largest file anyone ever attached. The sha256 is
    -- the address a later blob endpoint would serve them from.
    CREATE TABLE IF NOT EXISTS attachments (
      uuid       TEXT NOT NULL,
      user_id    TEXT NOT NULL,
      task_uuid  TEXT NOT NULL,
      filename   TEXT NOT NULL,
      size       INTEGER,
      sha256     TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      seq        INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );

    CREATE TABLE IF NOT EXISTS side_thoughts (
      uuid        TEXT NOT NULL,
      user_id     TEXT NOT NULL,
      text        TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      resolved_at TEXT,
      updated_at  TEXT NOT NULL,
      deleted_at  TEXT,
      seq         INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );

    -- A per-workspace journal: timestamped notes. Unlike side_thoughts this
    -- carries a workspace_uuid, since the log belongs to one workspace rather
    -- than the whole account.
    -- The journal's title and text are ciphertext whenever encrypted is 1:
    -- encryption is optional on the client (on only when a password is set),
    -- and when it is on the server stores and relays AES-GCM blobs it cannot
    -- read. That is deliberate - the server stays zero-knowledge about any
    -- encrypted journal content.
    CREATE TABLE IF NOT EXISTS journal_entries (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
      workspace_uuid TEXT NOT NULL,
      title          TEXT NOT NULL DEFAULT '',
      text           TEXT NOT NULL,
      encrypted      INTEGER NOT NULL DEFAULT 0,
      created_at     TEXT NOT NULL,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT,
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );

    -- A calendar is a coloured container for events. workspace_uuid is set
    -- when the calendar belongs to a workspace, in which case its uuid is that
    -- workspace's uuid, and null for a standalone one ("Workout"). Nullable
    -- here for the same reason review_every_days is: the merge writes whatever
    -- the push carried, and a NOT NULL would turn one malformed row into a
    -- rejected sync for the whole device.
    CREATE TABLE IF NOT EXISTS calendars (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
      workspace_uuid TEXT,
      name           TEXT,
      color          TEXT,
      notify_minutes INTEGER,
      sort_order     INTEGER NOT NULL DEFAULT 0,
      created_at     TEXT NOT NULL,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT,
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );

    -- start_at/end_at are UTC instants, not wall-clock readings, so an event
    -- keeps its moment when a device crosses a timezone. notify_minutes is the
    -- per-event override of its calendar's rule: null inherits, -1 is silent.
    CREATE TABLE IF NOT EXISTS calendar_events (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
      calendar_uuid  TEXT NOT NULL,
      title          TEXT NOT NULL,
      description    TEXT,
      start_at       TEXT NOT NULL,
      end_at         TEXT NOT NULL,
      notify_minutes INTEGER,
      created_at     TEXT NOT NULL,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT,
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );

    CREATE INDEX IF NOT EXISTS idx_workspaces_pull      ON workspaces      (user_id, seq);
    CREATE INDEX IF NOT EXISTS idx_tasks_pull           ON tasks           (user_id, seq);
    CREATE INDEX IF NOT EXISTS idx_side_thoughts_pull   ON side_thoughts   (user_id, seq);
    CREATE INDEX IF NOT EXISTS idx_parked_groups_pull   ON parked_groups   (user_id, seq);
    CREATE INDEX IF NOT EXISTS idx_attachments_pull     ON attachments     (user_id, seq);
    CREATE INDEX IF NOT EXISTS idx_journal_entries_pull ON journal_entries (user_id, seq);
    CREATE INDEX IF NOT EXISTS idx_calendars_pull       ON calendars       (user_id, seq);
    CREATE INDEX IF NOT EXISTS idx_calendar_events_pull ON calendar_events (user_id, seq);
  `);

  // `CREATE TABLE IF NOT EXISTS` above does nothing to a database that already
  // exists, so columns added later need adding explicitly. A server that has
  // been running since before reminders would otherwise reject every task push
  // with "no column named remind_at".
  addColumn(db, 'tasks', 'remind_at', 'TEXT');
  addColumn(db, 'tasks', 'group_uuid', 'TEXT');
  // A server that first synced a journal before entries had titles has the
  // table but not these columns; without them a journal push would fail.
  addColumn(db, 'journal_entries', 'title', "TEXT NOT NULL DEFAULT ''");
  addColumn(db, 'journal_entries', 'encrypted', 'INTEGER NOT NULL DEFAULT 0');
  // Attachments gained a second possible owner when calendar events could
  // carry them. A server that predates the calendar has the table but not the
  // column, and would reject every attachment push without this.
  addColumn(db, 'attachments', 'event_uuid', 'TEXT');
}

/**
 * Add a column if the table does not already have it. SQLite has no
 * `ADD COLUMN IF NOT EXISTS`, so the check is against the table info.
 */
function addColumn(db, table, column, type) {
  const has = db
    .prepare(`SELECT 1 FROM pragma_table_info(?) WHERE name = ?`)
    .get(table, column);
  if (!has) db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`);
}

// Column lists drive the generic merge below. `uuid` and the sync bookkeeping
// columns are handled separately, so these are the payload fields only.
export const TABLES = {
  workspaces: ['name', 'color', 'sort_order', 'created_at'],
  parked_groups: [
    'workspace_uuid',
    'title',
    'review_every_days',
    'last_reviewed_at',
    'sort_order',
    'created_at',
  ],
  tasks: [
    'workspace_uuid',
    'text',
    'created_at',
    'completed_at',
    'sort_order',
    'in_progress',
    'remind_at',
    'group_uuid',
  ],
  attachments: [
    'task_uuid',
    'event_uuid',
    'filename',
    'size',
    'sha256',
    'created_at',
  ],
  side_thoughts: ['text', 'created_at', 'resolved_at'],
  journal_entries: ['workspace_uuid', 'title', 'text', 'encrypted', 'created_at'],
  calendars: [
    'workspace_uuid',
    'name',
    'color',
    'notify_minutes',
    'sort_order',
    'created_at',
  ],
  calendar_events: [
    'calendar_uuid',
    'title',
    'description',
    'start_at',
    'end_at',
    'notify_minutes',
    'created_at',
  ],
};

function nextSeq(db) {
  db.prepare("UPDATE meta SET value = CAST(value AS INTEGER) + 1 WHERE key = 'seq'").run();
  return Number(db.prepare("SELECT value FROM meta WHERE key = 'seq'").get().value);
}

export function currentSeq(db) {
  return Number(db.prepare("SELECT value FROM meta WHERE key = 'seq'").get().value);
}

/**
 * Merge one incoming row, last-write-wins on `updated_at`.
 * Returns true if the row was actually written.
 */
function mergeRow(db, table, userId, row) {
  const fields = TABLES[table];
  const existing = db
    .prepare(`SELECT updated_at FROM ${table} WHERE user_id = ? AND uuid = ?`)
    .get(userId, row.uuid);

  // Ties go to the incumbent: a device replaying an unchanged row must not
  // churn the seq and re-broadcast itself to every other peer.
  if (existing && !(row.updated_at > existing.updated_at)) return false;

  const seq = nextSeq(db);
  const cols = ['uuid', 'user_id', ...fields, 'updated_at', 'deleted_at', 'seq'];
  const values = [
    row.uuid,
    userId,
    ...fields.map((f) => row[f] ?? null),
    row.updated_at,
    row.deleted_at ?? null,
    seq,
  ];

  db.prepare(
    `INSERT OR REPLACE INTO ${table} (${cols.join(', ')})
     VALUES (${cols.map(() => '?').join(', ')})`
  ).run(...values);
  return true;
}

/**
 * `in_progress` is globally exclusive - at most one task may carry it.
 *
 * Sync can break that invariant in a way single-device code never could: two
 * devices each focus a different task while offline, and both rows arrive with
 * in_progress = 1 on *different* uuids, so per-row LWW leaves both set. Resolve
 * it the same way the rest of the merge resolves conflicts - newest write wins,
 * everything older gets cleared.
 */
function enforceSingleInProgress(db, userId) {
  const flagged = db
    .prepare(
      `SELECT uuid, updated_at FROM tasks
        WHERE user_id = ? AND in_progress = 1 AND deleted_at IS NULL
        ORDER BY updated_at DESC, uuid DESC`
    )
    .all(userId);

  if (flagged.length <= 1) return;

  for (const loser of flagged.slice(1)) {
    db.prepare(
      `UPDATE tasks SET in_progress = 0, seq = ? WHERE user_id = ? AND uuid = ?`
    ).run(nextSeq(db), userId, loser.uuid);
  }
}

/**
 * The whole sync operation, in one transaction.
 *
 * Push and pull must share a transaction. If the pull read happened after the
 * write transaction closed, a concurrent write from another device could land
 * in between - it would get a seq below the cursor we return, and this client
 * would skip it forever.
 */
export function sync(db, userId, since, incoming) {
  const run = db.transaction(() => {
    for (const table of Object.keys(TABLES)) {
      for (const row of incoming[table] ?? []) {
        mergeRow(db, table, userId, row);
      }
    }
    enforceSingleInProgress(db, userId);

    const changes = {};
    for (const table of Object.keys(TABLES)) {
      changes[table] = db
        .prepare(`SELECT * FROM ${table} WHERE user_id = ? AND seq > ? ORDER BY seq`)
        .all(userId, since)
        .map(({ user_id, ...rest }) => rest);
    }
    return { cursor: currentSeq(db), changes };
  });

  return run();
}
