// Sync merge tests. Run with: npm run test:server
//
// These cover the cases that only appear once there is more than one device,
// which is exactly the class of bug that is miserable to debug from a phone.

import test from 'node:test';
import assert from 'node:assert/strict';
import Database from 'better-sqlite3';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openDb, sync, currentSeq } from './db.js';
import { identify, AuthError, LAN_USER } from './auth.js';

const USER = 'local';

function freshDb() {
  // Each test gets its own in-memory database.
  return openDb(':memory:');
}

function task(uuid, text, updated_at, extra = {}) {
  return {
    uuid,
    workspace_uuid: 'ws-1',
    text,
    created_at: '2026-07-21T10:00:00+02:00',
    completed_at: null,
    sort_order: 0,
    in_progress: 0,
    updated_at,
    deleted_at: null,
    ...extra,
  };
}

test('a pushed row comes back on a fresh pull', () => {
  const db = freshDb();
  const { cursor, changes } = sync(db, USER, 0, {
    tasks: [task('t1', 'buy milk', '2026-07-21T10:00:00+02:00')],
  });

  assert.equal(changes.tasks.length, 1);
  assert.equal(changes.tasks[0].text, 'buy milk');
  assert.ok(cursor > 0);

  // A second device starting from scratch sees it too.
  const second = sync(db, USER, 0, {});
  assert.equal(second.changes.tasks.length, 1);
});

test('later updated_at wins; earlier is ignored', () => {
  const db = freshDb();
  sync(db, USER, 0, { tasks: [task('t1', 'original', '2026-07-21T10:00:00+02:00')] });

  // Device B edited it later.
  sync(db, USER, 0, { tasks: [task('t1', 'newer', '2026-07-21T11:00:00+02:00')] });
  let state = sync(db, USER, 0, {});
  assert.equal(state.changes.tasks[0].text, 'newer');

  // Device C pushes a stale edit. It must not clobber the newer text.
  sync(db, USER, 0, { tasks: [task('t1', 'stale', '2026-07-21T09:00:00+02:00')] });
  state = sync(db, USER, 0, {});
  assert.equal(state.changes.tasks[0].text, 'newer');
});

test('re-pushing an unchanged row does not bump the cursor', () => {
  const db = freshDb();
  const row = task('t1', 'stable', '2026-07-21T10:00:00+02:00');
  sync(db, USER, 0, { tasks: [row] });
  const before = currentSeq(db);

  sync(db, USER, before, { tasks: [row] });
  assert.equal(currentSeq(db), before, 'identical row should be a no-op');
});

test('deletes propagate as tombstones, not disappearances', () => {
  const db = freshDb();
  sync(db, USER, 0, { tasks: [task('t1', 'doomed', '2026-07-21T10:00:00+02:00')] });
  const afterCreate = currentSeq(db);

  sync(db, USER, afterCreate, {
    tasks: [
      task('t1', 'doomed', '2026-07-21T12:00:00+02:00', {
        deleted_at: '2026-07-21T12:00:00+02:00',
      }),
    ],
  });

  // The peer must receive the row *with* a tombstone, so it knows to remove
  // its own copy. A silently missing row would be indistinguishable from
  // "never synced".
  const peer = sync(db, USER, afterCreate, {});
  assert.equal(peer.changes.tasks.length, 1);
  assert.equal(peer.changes.tasks[0].deleted_at, '2026-07-21T12:00:00+02:00');
});

test('incremental pull returns only what changed since the cursor', () => {
  const db = freshDb();
  const first = sync(db, USER, 0, {
    tasks: [task('t1', 'one', '2026-07-21T10:00:00+02:00')],
  });

  const second = sync(db, USER, first.cursor, {
    tasks: [task('t2', 'two', '2026-07-21T10:05:00+02:00')],
  });

  const uuids = second.changes.tasks.map((t) => t.uuid);
  assert.deepEqual(uuids, ['t2'], 't1 was already known to this client');
});

test('in_progress stays globally exclusive across a two-device conflict', () => {
  const db = freshDb();

  // Both devices focused a different task while offline, and both rows are
  // legitimately in_progress = 1 on their own uuid. Per-row LWW alone would
  // leave both set, because they never touch the same row.
  sync(db, USER, 0, {
    tasks: [
      task('t1', 'device A focus', '2026-07-21T10:00:00+02:00', { in_progress: 1 }),
      task('t2', 'device B focus', '2026-07-21T11:00:00+02:00', { in_progress: 1 }),
    ],
  });

  const state = sync(db, USER, 0, {});
  const focused = state.changes.tasks.filter((t) => t.in_progress === 1);
  assert.equal(focused.length, 1, 'at most one task may be in progress');
  assert.equal(focused[0].uuid, 't2', 'the most recently focused task wins');
});

test('workspaces and side thoughts round-trip independently', () => {
  const db = freshDb();
  const { changes } = sync(db, USER, 0, {
    workspaces: [
      {
        uuid: 'ws-1',
        name: 'Tasks',
        color: '#6c8cff',
        sort_order: 0,
        created_at: '2026-07-21T09:00:00+02:00',
        updated_at: '2026-07-21T09:00:00+02:00',
      },
    ],
    side_thoughts: [
      {
        uuid: 'st-1',
        text: 'look into flutter',
        created_at: '2026-07-21T09:30:00+02:00',
        resolved_at: null,
        updated_at: '2026-07-21T09:30:00+02:00',
      },
    ],
  });

  assert.equal(changes.workspaces[0].name, 'Tasks');
  assert.equal(changes.side_thoughts[0].text, 'look into flutter');
});

test('a reminder set on one device reaches the others', () => {
  const db = freshDb();

  sync(db, USER, 0, {
    tasks: [
      task('t-1', 'call the dentist', '2026-07-21T10:00:00+02:00', {
        remind_at: '2026-07-21T14:00:00.000Z',
      }),
    ],
  });

  const { changes } = sync(db, USER, 0, {});
  assert.equal(changes.tasks[0].remind_at, '2026-07-21T14:00:00.000Z');
});

test('clearing a reminder propagates as a null, not a stale value', () => {
  const db = freshDb();

  sync(db, USER, 0, {
    tasks: [
      task('t-1', 'call the dentist', '2026-07-21T10:00:00+02:00', {
        remind_at: '2026-07-21T14:00:00.000Z',
      }),
    ],
  });
  // Same row, later write, reminder removed. A merge that only copied
  // non-null fields would leave the old time armed on every other device.
  const { changes } = sync(db, USER, 0, {
    tasks: [
      task('t-1', 'call the dentist', '2026-07-21T11:00:00+02:00', {
        remind_at: null,
      }),
    ],
  });

  assert.equal(changes.tasks[0].remind_at, null);
});

test('a server database predating reminders gains the column', () => {
  // openDb() on an existing file only runs CREATE TABLE IF NOT EXISTS, so
  // without an explicit migration the column would never appear and every
  // task push would fail.
  const dir = mkdtempSync(join(tmpdir(), 'todo-server-'));
  const path = join(dir, 'sync.db');

  const legacy = new Database(path);
  legacy.exec(`
    CREATE TABLE tasks (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
      workspace_uuid TEXT NOT NULL,
      text           TEXT NOT NULL,
      created_at     TEXT NOT NULL,
      completed_at   TEXT,
      sort_order     INTEGER NOT NULL DEFAULT 0,
      in_progress    INTEGER NOT NULL DEFAULT 0,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT,
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );
    INSERT INTO tasks (uuid, user_id, workspace_uuid, text, created_at, updated_at, seq)
    VALUES ('old-1', 'local', 'ws-1', 'from before reminders', '2026-01-01T09:00:00Z', '2026-01-01T09:00:00Z', 1);
  `);
  legacy.close();

  const db = openDb(path);
  sync(db, USER, 0, {
    tasks: [
      task('t-1', 'new one', '2026-07-21T10:00:00+02:00', {
        remind_at: '2026-07-21T14:00:00.000Z',
      }),
    ],
  });

  const { changes } = sync(db, USER, 0, {});
  const byUuid = Object.fromEntries(changes.tasks.map((t) => [t.uuid, t]));
  assert.equal(byUuid['t-1'].remind_at, '2026-07-21T14:00:00.000Z');
  // The pre-existing row survives the migration.
  assert.equal(byUuid['old-1'].text, 'from before reminders');

  db.close();
  rmSync(dir, { recursive: true, force: true });
});

test('a parked group and its membership sync together', () => {
  const db = freshDb();

  sync(db, USER, 0, {
    parked_groups: [
      {
        uuid: 'g-1',
        workspace_uuid: 'ws-1',
        title: 'Backlog',
        review_every_days: 30,
        last_reviewed_at: null,
        sort_order: 0,
        created_at: '2026-07-21T10:00:00+02:00',
        updated_at: '2026-07-21T10:00:00+02:00',
        deleted_at: null,
      },
    ],
    tasks: [
      task('t-1', 'someday', '2026-07-21T10:00:00+02:00', {
        group_uuid: 'g-1',
      }),
    ],
  });

  const { changes } = sync(db, USER, 0, {});
  assert.equal(changes.parked_groups.length, 1);
  assert.equal(changes.parked_groups[0].title, 'Backlog');
  assert.equal(changes.parked_groups[0].review_every_days, 30);
  // Membership lives on the task, so a device that merges both ends up with
  // the task shelved rather than back on its current list.
  assert.equal(changes.tasks[0].group_uuid, 'g-1');
});

test('unparking propagates as a null group, not a stale one', () => {
  const db = freshDb();

  sync(db, USER, 0, {
    tasks: [
      task('t-1', 'someday', '2026-07-21T10:00:00+02:00', {
        group_uuid: 'g-1',
      }),
    ],
  });
  const { changes } = sync(db, USER, 0, {
    tasks: [
      task('t-1', 'someday', '2026-07-21T11:00:00+02:00', {
        group_uuid: null,
      }),
    ],
  });

  assert.equal(changes.tasks[0].group_uuid, null);
});

test('a server database predating parked groups gains the table and column', () => {
  const dir = mkdtempSync(join(tmpdir(), 'todo-server-'));
  const path = join(dir, 'sync.db');

  const legacy = new Database(path);
  legacy.exec(`
    CREATE TABLE tasks (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
      workspace_uuid TEXT NOT NULL,
      text           TEXT NOT NULL,
      created_at     TEXT NOT NULL,
      completed_at   TEXT,
      sort_order     INTEGER NOT NULL DEFAULT 0,
      in_progress    INTEGER NOT NULL DEFAULT 0,
      remind_at      TEXT,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT,
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );
    INSERT INTO tasks (uuid, user_id, workspace_uuid, text, created_at, updated_at, seq)
    VALUES ('old-1', 'local', 'ws-1', 'from before groups', '2026-01-01T09:00:00Z', '2026-01-01T09:00:00Z', 1);
  `);
  legacy.close();

  const db = openDb(path);
  sync(db, USER, 0, {
    tasks: [
      task('t-1', 'shelved', '2026-07-21T10:00:00+02:00', {
        group_uuid: 'g-1',
      }),
    ],
  });

  const { changes } = sync(db, USER, 0, {});
  const byUuid = Object.fromEntries(changes.tasks.map((t) => [t.uuid, t]));
  assert.equal(byUuid['t-1'].group_uuid, 'g-1');
  assert.equal(byUuid['old-1'].text, 'from before groups');

  db.close();
  rmSync(dir, { recursive: true, force: true });
});

test('attachment metadata syncs, and the bytes are not the server\'s problem', () => {
  const db = freshDb();

  const { changes } = sync(db, USER, 0, {
    attachments: [
      {
        uuid: 'a-1',
        task_uuid: 't-1',
        filename: 'tax-return.pdf',
        size: 412000,
        sha256: 'f'.repeat(64),
        created_at: '2026-07-21T10:00:00+02:00',
        updated_at: '2026-07-21T10:00:00+02:00',
        deleted_at: null,
      },
    ],
  });

  assert.equal(changes.attachments.length, 1);
  assert.equal(changes.attachments[0].filename, 'tax-return.pdf');
  // The digest is the whole point: it is the address a later blob endpoint
  // would serve from, so it has to survive the round trip intact.
  assert.equal(changes.attachments[0].sha256, 'f'.repeat(64));
  // There is no column for the contents, and deliberately so.
  assert.ok(!('data' in changes.attachments[0]));
});

test('a removed attachment propagates as a tombstone', () => {
  const db = freshDb();
  const row = (updated_at, deleted_at) => ({
    uuid: 'a-1',
    task_uuid: 't-1',
    filename: 'notes.md',
    size: 120,
    sha256: 'e'.repeat(64),
    created_at: '2026-07-21T10:00:00+02:00',
    updated_at,
    deleted_at,
  });

  sync(db, USER, 0, { attachments: [row('2026-07-21T10:00:00+02:00', null)] });
  const { changes } = sync(db, USER, 0, {
    attachments: [row('2026-07-21T11:00:00+02:00', '2026-07-21T11:00:00+02:00')],
  });

  assert.equal(changes.attachments[0].deleted_at, '2026-07-21T11:00:00+02:00');
});

test('a server database predating attachments gains the table', () => {
  const dir = mkdtempSync(join(tmpdir(), 'todo-server-'));
  const path = join(dir, 'sync.db');

  const legacy = new Database(path);
  legacy.exec(`
    CREATE TABLE tasks (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
      workspace_uuid TEXT NOT NULL,
      text           TEXT NOT NULL,
      created_at     TEXT NOT NULL,
      completed_at   TEXT,
      sort_order     INTEGER NOT NULL DEFAULT 0,
      in_progress    INTEGER NOT NULL DEFAULT 0,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT,
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );
    INSERT INTO tasks (uuid, user_id, workspace_uuid, text, created_at, updated_at, seq)
    VALUES ('old-1', 'local', 'ws-1', 'from before attachments', '2026-01-01T09:00:00Z', '2026-01-01T09:00:00Z', 1);
  `);
  legacy.close();

  const db = openDb(path);
  const { changes } = sync(db, USER, 0, {
    attachments: [
      {
        uuid: 'a-1',
        task_uuid: 'old-1',
        filename: 'receipt.png',
        size: 900,
        sha256: 'd'.repeat(64),
        created_at: '2026-07-21T10:00:00+02:00',
        updated_at: '2026-07-21T10:00:00+02:00',
        deleted_at: null,
      },
    ],
  });

  assert.equal(changes.attachments[0].filename, 'receipt.png');
  assert.equal(changes.tasks[0].text, 'from before attachments');

  db.close();
  rmSync(dir, { recursive: true, force: true });
});

test('journal entries round-trip title and body as opaque ciphertext', () => {
  const db = freshDb();

  // When encrypted, the client sends AES-GCM blobs and the encrypted flag; the
  // server neither reads nor cares. Any string stands in for the blobs here -
  // what matters is they, and the flag, survive untouched.
  const { changes } = sync(db, USER, 0, {
    journal_entries: [
      {
        uuid: 'j-1',
        workspace_uuid: 'ws-1',
        title: 'ENC(title)',
        text: 'ENC(body)',
        encrypted: 1,
        created_at: '2026-07-23T14:00:00+02:00',
        updated_at: '2026-07-23T14:00:00+02:00',
        deleted_at: null,
      },
    ],
  });

  assert.equal(changes.journal_entries.length, 1);
  assert.equal(changes.journal_entries[0].title, 'ENC(title)');
  assert.equal(changes.journal_entries[0].text, 'ENC(body)');
  assert.equal(changes.journal_entries[0].encrypted, 1);
  // The workspace is a payload field, not bookkeeping - a note that lost it
  // would surface in the wrong workspace on the next device.
  assert.equal(changes.journal_entries[0].workspace_uuid, 'ws-1');
});

test('a plaintext journal entry round-trips with encrypted = 0', () => {
  const db = freshDb();
  const { changes } = sync(db, USER, 0, {
    journal_entries: [
      {
        uuid: 'j-1',
        workspace_uuid: 'ws-1',
        title: 'a plain title',
        text: 'a plain body',
        encrypted: 0,
        created_at: '2026-07-23T14:00:00+02:00',
        updated_at: '2026-07-23T14:00:00+02:00',
        deleted_at: null,
      },
    ],
  });
  assert.equal(changes.journal_entries[0].encrypted, 0);
  assert.equal(changes.journal_entries[0].text, 'a plain body');
});

test('editing a journal entry wins by updated_at, keeping created_at', () => {
  const db = freshDb();
  const entry = (text, updated_at) => ({
    uuid: 'j-1',
    workspace_uuid: 'ws-1',
    text,
    created_at: '2026-07-23T14:00:00+02:00',
    updated_at,
    deleted_at: null,
  });

  sync(db, USER, 0, { journal_entries: [entry('typo', '2026-07-23T14:00:00+02:00')] });
  const { changes } = sync(db, USER, 0, {
    journal_entries: [entry('fixed', '2026-07-23T15:00:00+02:00')],
  });

  assert.equal(changes.journal_entries[0].text, 'fixed');
  // The edit moved updated_at but not created_at - the log keeps its order.
  assert.equal(changes.journal_entries[0].created_at, '2026-07-23T14:00:00+02:00');
});

test('a deleted journal entry propagates as a tombstone', () => {
  const db = freshDb();
  const row = (updated_at, deleted_at) => ({
    uuid: 'j-1',
    workspace_uuid: 'ws-1',
    text: 'logged, then removed',
    created_at: '2026-07-23T14:00:00+02:00',
    updated_at,
    deleted_at,
  });

  sync(db, USER, 0, { journal_entries: [row('2026-07-23T14:00:00+02:00', null)] });
  const { changes } = sync(db, USER, 0, {
    journal_entries: [row('2026-07-23T15:00:00+02:00', '2026-07-23T15:00:00+02:00')],
  });

  assert.equal(changes.journal_entries[0].deleted_at, '2026-07-23T15:00:00+02:00');
});

test('a server database predating the journal gains the table', () => {
  const dir = mkdtempSync(join(tmpdir(), 'todo-server-'));
  const path = join(dir, 'sync.db');

  const legacy = new Database(path);
  legacy.exec(`
    CREATE TABLE tasks (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
      workspace_uuid TEXT NOT NULL,
      text           TEXT NOT NULL,
      created_at     TEXT NOT NULL,
      completed_at   TEXT,
      sort_order     INTEGER NOT NULL DEFAULT 0,
      in_progress    INTEGER NOT NULL DEFAULT 0,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT,
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );
    INSERT INTO tasks (uuid, user_id, workspace_uuid, text, created_at, updated_at, seq)
    VALUES ('old-1', 'local', 'ws-1', 'from before the journal', '2026-01-01T09:00:00Z', '2026-01-01T09:00:00Z', 1);
  `);
  legacy.close();

  const db = openDb(path);
  sync(db, USER, 0, {
    journal_entries: [
      {
        uuid: 'j-1',
        workspace_uuid: 'ws-1',
        text: 'first entry on the upgraded server',
        created_at: '2026-07-23T14:00:00+02:00',
        updated_at: '2026-07-23T14:00:00+02:00',
        deleted_at: null,
      },
    ],
  });

  const { changes } = sync(db, USER, 0, {});
  assert.equal(changes.journal_entries[0].text, 'first entry on the upgraded server');
  // The pre-existing row survives the migration.
  assert.equal(changes.tasks[0].text, 'from before the journal');

  db.close();
  rmSync(dir, { recursive: true, force: true });
});

test('a server database with a title-less journal gains the column', () => {
  // A server that first synced a journal in the v5 era has the table but no
  // title column; openDb must add it, or every titled push would fail.
  const dir = mkdtempSync(join(tmpdir(), 'todo-server-'));
  const path = join(dir, 'sync.db');

  const legacy = new Database(path);
  legacy.exec(`
    CREATE TABLE journal_entries (
      uuid           TEXT NOT NULL,
      user_id        TEXT NOT NULL,
      workspace_uuid TEXT NOT NULL,
      text           TEXT NOT NULL,
      created_at     TEXT NOT NULL,
      updated_at     TEXT NOT NULL,
      deleted_at     TEXT,
      seq            INTEGER NOT NULL,
      PRIMARY KEY (user_id, uuid)
    );
    INSERT INTO journal_entries (uuid, user_id, workspace_uuid, text, created_at, updated_at, seq)
    VALUES ('old-1', 'local', 'ws-1', 'ENC(before titles)', '2026-01-01T09:00:00Z', '2026-01-01T09:00:00Z', 1);
  `);
  legacy.close();

  const db = openDb(path);
  sync(db, USER, 0, {
    journal_entries: [
      {
        uuid: 'j-1',
        workspace_uuid: 'ws-1',
        title: 'ENC(new title)',
        text: 'ENC(new body)',
        created_at: '2026-07-23T14:00:00+02:00',
        updated_at: '2026-07-23T14:00:00+02:00',
        deleted_at: null,
      },
    ],
  });

  const { changes } = sync(db, USER, 0, {});
  const byUuid = Object.fromEntries(changes.journal_entries.map((e) => [e.uuid, e]));
  assert.equal(byUuid['j-1'].title, 'ENC(new title)');
  // The pre-existing row survives, with an empty title from the DEFAULT.
  assert.equal(byUuid['old-1'].text, 'ENC(before titles)');
  assert.equal(byUuid['old-1'].title, '');

  db.close();
  rmSync(dir, { recursive: true, force: true });
});

test('auth rejects a missing, malformed or wrong token', () => {
  const config = { secret: 'correct-horse' };
  const req = (auth) => ({ get: () => auth });

  assert.throws(() => identify(req(undefined), config), AuthError);
  assert.throws(() => identify(req('correct-horse'), config), AuthError, 'needs Bearer prefix');
  assert.throws(() => identify(req('Bearer wrong'), config), AuthError);
  assert.throws(() => identify(req('Bearer correct-hors'), config), AuthError);

  assert.equal(identify(req('Bearer correct-horse'), config), LAN_USER);
});
