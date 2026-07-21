// Sync merge tests. Run with: npm run test:server
//
// These cover the cases that only appear once there is more than one device,
// which is exactly the class of bug that is miserable to debug from a phone.

import test from 'node:test';
import assert from 'node:assert/strict';
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

test('auth rejects a missing, malformed or wrong token', () => {
  const config = { secret: 'correct-horse' };
  const req = (auth) => ({ get: () => auth });

  assert.throws(() => identify(req(undefined), config), AuthError);
  assert.throws(() => identify(req('correct-horse'), config), AuthError, 'needs Bearer prefix');
  assert.throws(() => identify(req('Bearer wrong'), config), AuthError);
  assert.throws(() => identify(req('Bearer correct-hors'), config), AuthError);

  assert.equal(identify(req('Bearer correct-horse'), config), LAN_USER);
});
