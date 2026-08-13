// Live change hints. Run with: npm run test:server
//
// The property under test is not "a message arrives" - it is *who* it arrives
// at. A hint says "your account moved", so sending one to the wrong account
// leaks the fact that somebody else is working, and sending one back to the
// device that just pushed costs it a pointless round trip on every keystroke.
//
// The connections here are fake `res` objects rather than real sockets. That is
// deliberate: what this file is checking is the fan-out bookkeeping, and a real
// HTTP server would only add a way for these tests to hang.

import test from 'node:test';
import assert from 'node:assert/strict';

import { closeAll, connectionCount, publish, subscribe } from './events.js';
import { openDb, sync } from './db.js';

/** Just enough of a ServerResponse for events.js to write to. */
function fakeRes() {
  const handlers = {};
  return {
    chunks: [],
    ended: false,
    status: null,
    headers: null,
    writeHead(status, headers) {
      this.status = status;
      this.headers = headers;
    },
    flushHeaders() {},
    socket: { setTimeout() {}, setNoDelay() {} },
    write(chunk) {
      if (this.ended) throw new Error('write after end');
      this.chunks.push(chunk);
      return true;
    },
    end() {
      this.ended = true;
      handlers.close?.();
    },
    on(event, fn) {
      handlers[event] = fn;
    },
    /** The `event:` names received, in order, ignoring heartbeat comments. */
    names() {
      return this.chunks
        .join('')
        .split('\n\n')
        .filter((block) => block.startsWith('event: '))
        .map((block) => block.slice(7).split('\n')[0]);
    },
    data() {
      return this.chunks
        .join('')
        .split('\n\n')
        .filter((block) => block.includes('\ndata: '))
        .map((block) => JSON.parse(block.split('\ndata: ')[1]));
    },
  };
}

test.afterEach(() => closeAll());

test('a new connection is told the stream works', async () => {
  const res = fakeRes();
  subscribe('alice', 'phone', res);

  // Silence is indistinguishable from a proxy eating the response, so the
  // first thing down the pipe has to be something.
  assert.deepEqual(res.names(), ['ready']);
  assert.equal(res.status, 200);
  assert.match(res.headers['Content-Type'], /text\/event-stream/);
  assert.match(res.headers['Cache-Control'], /no-cache/);
});

test('a hint reaches a user and nobody else', async () => {
  const alice = fakeRes();
  const bob = fakeRes();
  subscribe('alice', 'laptop', alice);
  subscribe('bob', 'laptop', bob);

  assert.equal(publish('alice', 42), 1);

  assert.deepEqual(alice.names(), ['ready', 'changed']);
  assert.deepEqual(alice.data().at(-1), { cursor: 42 });
  // Bob shares the server, and its global seq counter, and must learn nothing
  // from either.
  assert.deepEqual(bob.names(), ['ready']);
});

test('every device of one user is told', async () => {
  const phone = fakeRes();
  const laptop = fakeRes();
  subscribe('alice', 'phone', phone);
  subscribe('alice', 'laptop', laptop);

  assert.equal(publish('alice', 7), 2);
  assert.equal(connectionCount('alice'), 2);
});

test('the device that pushed is not told about its own push', async () => {
  const phone = fakeRes();
  const laptop = fakeRes();
  subscribe('alice', 'phone', phone);
  subscribe('alice', 'laptop', laptop);

  assert.equal(publish('alice', 7, 'phone'), 1);
  assert.deepEqual(phone.names(), ['ready'], 'it already has these rows');
  assert.deepEqual(laptop.names(), ['ready', 'changed']);
});

test('a closed connection stops receiving and is forgotten', async () => {
  const res = fakeRes();
  subscribe('alice', 'phone', res);
  assert.equal(connectionCount('alice'), 1);

  res.end();
  assert.equal(connectionCount('alice'), 0);

  // Publishing to a user with nothing open is a no-op, not a throw: a phone
  // going into a tunnel must not be able to fail somebody else's sync.
  assert.equal(publish('alice', 9), 0);
});

test('publishing to a user who has never connected is harmless', async () => {
  assert.equal(publish('nobody', 1), 0);
  assert.equal(connectionCount(), 0);
});

// ------------------------------------------------------------------ the trigger
//
// A hint is only worth sending when rows actually landed. `sync` reports that
// as `merged`, and these pin the two cases that decide it - because getting it
// wrong in the generous direction makes every device wake every other device up
// on every poll, which is worse than no hints at all.

function task(uuid, text, updated_at) {
  return {
    uuid,
    workspace_uuid: 'ws-1',
    text,
    created_at: '2026-08-12T10:00:00+02:00',
    completed_at: null,
    sort_order: 0,
    in_progress: 0,
    updated_at,
    deleted_at: null,
  };
}

test('a push that writes rows reports them as merged', async () => {
  const db = openDb(':memory:');
  const result = sync(db, 'alice', 0, {
    tasks: [task('t-1', 'one', '2026-08-12T10:00:00Z')],
  });
  assert.equal(result.merged, 1);
});

test('a push that changes nothing merges nothing', async () => {
  const db = openDb(':memory:');
  const row = task('t-1', 'one', '2026-08-12T10:00:00Z');
  sync(db, 'alice', 0, { tasks: [row] });

  // The same row again, unchanged - a client replaying what it already sent.
  // Ties go to the incumbent, so nothing is written and nobody is woken.
  const again = sync(db, 'alice', 0, { tasks: [row] });
  assert.equal(again.merged, 0);
});

test('merged is not part of what the client is told', async () => {
  // It describes what the server did, not what the caller now has. The route
  // strips it; this is the reminder that it is the route's job.
  const db = openDb(':memory:');
  const result = sync(db, 'alice', 0, {
    tasks: [task('t-1', 'one', '2026-08-12T10:00:00Z')],
  });
  assert.deepEqual(Object.keys(result).sort(), ['changes', 'cursor', 'merged']);
});
