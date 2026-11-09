import assert from 'node:assert/strict';
import { test } from 'node:test';

import { openDb, purgeUser, storedFor, sync } from './db.js';
import { createUser } from './users.js';
import {
  KEEP_DAYS,
  dayOf,
  daysBefore,
  pruneTraffic,
  recordHit,
  trafficOverview,
  trafficRecorder,
} from './traffic.js';

const now = new Date(2026, 10, 9, 12, 0);

test('hits on one day add up in one row per account', () => {
  const db = openDb(':memory:');
  recordHit(db, 'a', { sync: true, rowsIn: 3, rowsOut: 5, bytesIn: 100, bytesOut: 200 }, '2026-11-09');
  recordHit(db, 'a', { bytesOut: 50 }, '2026-11-09');
  recordHit(db, 'b', { sync: true }, '2026-11-09');
  const rows = db.prepare('SELECT * FROM traffic ORDER BY user_id').all();
  assert.equal(rows.length, 2);
  assert.deepEqual(
    { ...rows[0] },
    {
      user_id: 'a',
      day: '2026-11-09',
      requests: 2,
      syncs: 1,
      rows_in: 3,
      rows_out: 5,
      bytes_in: 100,
      bytes_out: 250,
    }
  );
});

test('the overview has every day of the window, quiet ones as zeros', () => {
  const db = openDb(':memory:');
  recordHit(db, 'a', { sync: true }, dayOf(now));
  recordHit(db, 'a', {}, daysBefore(now, 2));
  recordHit(db, 'a', {}, daysBefore(now, 40)); // outside a 7-day window
  const o = trafficOverview(db, {
    days: 7,
    now,
    users: [{ id: 'a', label: 'Ann', is_admin: 1 }, { id: 'b', label: 'Bo', is_admin: 0 }],
    extra: (u) => ({ rows_stored: u.id === 'a' ? 9 : 0 }),
  });
  assert.equal(o.daily.length, 7);
  assert.equal(o.daily.at(-1).day, '2026-11-09');
  assert.equal(o.daily[0].day, '2026-11-03');
  assert.deepEqual(
    o.daily.map((d) => d.requests),
    [0, 0, 0, 0, 1, 0, 1]
  );
  assert.equal(o.totals.requests, 2);
  assert.equal(o.totals.syncs, 1);

  const [ann, bo] = o.users;
  assert.equal(ann.label, 'Ann');
  assert.equal(ann.admin, true);
  assert.equal(ann.requests, 2);
  assert.equal(ann.active_days, 2);
  assert.equal(ann.last_day, '2026-11-09');
  assert.equal(ann.rows_stored, 9);
  assert.equal(bo.requests, 0, 'an account with no traffic is still listed');
  assert.equal(bo.last_day, null);
});

test('days older than the keep window are pruned', () => {
  const db = openDb(':memory:');
  recordHit(db, 'a', {}, daysBefore(now, KEEP_DAYS + 1));
  recordHit(db, 'a', {}, daysBefore(now, KEEP_DAYS - 1));
  assert.equal(pruneTraffic(db, now), 1);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM traffic').get().n, 1);
});

test('the recorder counts only requests an account made, on finish', () => {
  const db = openDb(':memory:');
  const record = trafficRecorder(db);
  const run = (userId, locals = {}) => {
    const listeners = {};
    const req = { userId: null, get: (h) => (h === 'content-length' ? '10' : undefined) };
    const res = {
      locals,
      on: (event, fn) => (listeners[event] = fn),
      get: (h) => (h === 'content-length' ? '30' : undefined),
    };
    record(req, res, () => {
      req.userId = userId; // what a route's own auth does
    });
    listeners.finish();
  };
  run('a', { traffic: { sync: true, rowsIn: 2, rowsOut: 4 } });
  run(null);
  const rows = db.prepare('SELECT * FROM traffic').all();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].syncs, 1);
  assert.equal(rows[0].rows_out, 4);
  assert.equal(rows[0].bytes_in, 10);
  assert.equal(rows[0].bytes_out, 30);
});

test('stored counts live rows only, and deleting an account takes its traffic', () => {
  const db = openDb(':memory:');
  const u = createUser(db, 'Cy');
  const stamp = '2026-11-09T10:00:00+01:00';
  sync(db, u.id, 0, {
    side_thoughts: [
      { uuid: 't1', text: 'one', created_at: stamp, updated_at: stamp },
      { uuid: 't2', text: 'two', created_at: stamp, updated_at: stamp, deleted_at: stamp },
    ],
  });
  assert.deepEqual(storedFor(db, u.id), { rows: 1, blobBytes: 0 });
  recordHit(db, u.id, {}, '2026-11-09');
  purgeUser(db, u.id);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM traffic').get().n, 0);
});
