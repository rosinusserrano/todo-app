// Multi-user tests. Run with: npm run test:server
//
// Two things are being defended here, and only one of them is "the feature":
//
//   1. A second user is *isolated*. Every query in db.js is scoped by user_id,
//      and these tests are what says so out loud - an unscoped WHERE would show
//      up as one person's tasks arriving in another's pull.
//   2. The setup that existed before tokens keeps working, pointed at the same
//      rows. Those rows carry user_id 'local', so the bootstrap secret has to
//      keep resolving to exactly that.

import test from 'node:test';
import assert from 'node:assert/strict';
import { openDb, purgeUser, sync, currentSeq, userCursor } from './db.js';
import { identify, AuthError } from './auth.js';
import {
  LAN_USER,
  adoptBootstrapSecret,
  createUser,
  isAdmin,
  issueToken,
  listTokens,
  listUsers,
  resolveToken,
  revokeToken,
  setAdmin,
} from './users.js';

function freshDb() {
  return openDb(':memory:');
}

function task(uuid, text, updated_at, extra = {}) {
  return {
    uuid,
    workspace_uuid: 'ws-1',
    text,
    created_at: '2026-08-03T10:00:00+02:00',
    completed_at: null,
    sort_order: 0,
    in_progress: 0,
    updated_at,
    deleted_at: null,
    ...extra,
  };
}

const req = (auth) => ({ get: () => auth });

test('an issued token resolves to its own user', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const { token } = issueToken(db, alice.id, 'phone');

  assert.equal(resolveToken(db, token).userId, alice.id);
  assert.equal(await identify(req(`Bearer ${token}`), { db }), alice.id);
});

test('the token itself is never stored, only its hash', async () => {
  const db = freshDb();
  const bob = createUser(db, 'Bob');
  const { token } = issueToken(db, bob.id, 'laptop');

  // Anyone who can read the database file must not be able to read the token
  // out of it and sync as that user.
  const rows = db.prepare('SELECT * FROM tokens').all();
  for (const row of rows) {
    for (const value of Object.values(row)) {
      assert.notEqual(value, token);
    }
  }
});

test('two users on one server never see each other\'s rows', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const bob = createUser(db, 'Bob');

  sync(db, alice.id, 0, { tasks: [task('t-a', 'alice: taxes', '2026-08-03T10:00:00+02:00')] });
  sync(db, bob.id, 0, { tasks: [task('t-b', 'bob: groceries', '2026-08-03T10:00:00+02:00')] });

  const forAlice = sync(db, alice.id, 0, {});
  const forBob = sync(db, bob.id, 0, {});

  assert.deepEqual(forAlice.changes.tasks.map((t) => t.uuid), ['t-a']);
  assert.deepEqual(forBob.changes.tasks.map((t) => t.uuid), ['t-b']);
});

test('the same uuid can exist for two users without colliding', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const bob = createUser(db, 'Bob');

  // Not far-fetched: the client seeds a default workspace, and two people
  // restoring from the same legacy database would carry the same uuids.
  sync(db, alice.id, 0, { tasks: [task('shared-uuid', 'alice', '2026-08-03T10:00:00+02:00')] });
  sync(db, bob.id, 0, { tasks: [task('shared-uuid', 'bob', '2026-08-03T11:00:00+02:00')] });

  assert.equal(sync(db, alice.id, 0, {}).changes.tasks[0].text, 'alice');
  // Bob's write is *later*, so a merge that ignored user_id would have
  // overwritten Alice's row rather than sitting beside it.
  assert.equal(sync(db, bob.id, 0, {}).changes.tasks[0].text, 'bob');
});

test('one user focusing a task does not clear another user\'s focus', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const bob = createUser(db, 'Bob');

  sync(db, alice.id, 0, {
    tasks: [task('t-a', 'alice focus', '2026-08-03T10:00:00+02:00', { in_progress: 1 })],
  });
  // in_progress is globally exclusive, but "globally" means within an account:
  // the resolver runs per user, so Bob focusing later must not unfocus Alice.
  sync(db, bob.id, 0, {
    tasks: [task('t-b', 'bob focus', '2026-08-03T12:00:00+02:00', { in_progress: 1 })],
  });

  assert.equal(sync(db, alice.id, 0, {}).changes.tasks[0].in_progress, 1);
  assert.equal(sync(db, bob.id, 0, {}).changes.tasks[0].in_progress, 1);
});

test('a user\'s cursor does not move when someone else writes', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const bob = createUser(db, 'Bob');

  const { cursor } = sync(db, alice.id, 0, {
    tasks: [task('t-a', 'alice', '2026-08-03T10:00:00+02:00')],
  });

  const globalBefore = currentSeq(db);
  sync(db, bob.id, 0, { tasks: [task('t-b', 'bob', '2026-08-03T10:00:00+02:00')] });
  assert.ok(currentSeq(db) > globalBefore, 'the shared counter did advance');

  // If /api/cursor answered with that shared counter, Alice's client would see
  // a changed cursor and sync - fetching nothing - every time Bob typed.
  assert.equal(userCursor(db, alice.id), cursor);
  assert.equal(sync(db, alice.id, cursor, {}).changes.tasks.length, 0);
});

test('a cursor still catches the user\'s own later writes', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const bob = createUser(db, 'Bob');

  const first = sync(db, alice.id, 0, {
    tasks: [task('t-1', 'one', '2026-08-03T10:00:00+02:00')],
  });
  // Someone else's writes in between push the shared counter along; Alice's
  // next row must still land above the cursor she was handed.
  sync(db, bob.id, 0, { tasks: [task('t-b', 'bob', '2026-08-03T10:01:00+02:00')] });

  const second = sync(db, alice.id, first.cursor, {
    tasks: [task('t-2', 'two', '2026-08-03T10:02:00+02:00')],
  });
  assert.deepEqual(second.changes.tasks.map((t) => t.uuid), ['t-2']);
  assert.ok(second.cursor > first.cursor);
});

test('a revoked token stops working, and takes only itself down', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const phone = issueToken(db, alice.id, 'phone');
  const laptop = issueToken(db, alice.id, 'laptop');

  assert.equal(revokeToken(db, phone.id), true);
  assert.equal(resolveToken(db, phone.token), null);
  await assert.rejects(() => identify(req(`Bearer ${phone.token}`), { db }), AuthError);
  // The user's other device is unaffected - revoking is per token, which is the
  // point of issuing one per device.
  assert.equal(resolveToken(db, laptop.token).userId, alice.id);

  // Revoking twice is not an error worth crashing over, but it must report that
  // it did nothing, so the CLI can say so.
  assert.equal(revokeToken(db, phone.id), false);
});

test('a revoked token cannot be resurrected by the bootstrap secret path', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const { token, id } = issueToken(db, alice.id, 'phone');
  revokeToken(db, id);

  // identify() has no "or compare against the configured secret" fallback, so
  // there is no branch that could accept a token the table has revoked.
  adoptBootstrapSecret(db, 'the-owners-secret');
  await assert.rejects(() => identify(req(`Bearer ${token}`), { db }), AuthError);
});

test('the bootstrap secret is adopted as the local user, once', async () => {
  const db = freshDb();

  // A pre-multi-user server's rows are already user_id 'local'.
  sync(db, LAN_USER, 0, { tasks: [task('t-old', 'from before tokens', '2026-01-01T09:00:00Z')] });

  adoptBootstrapSecret(db, 'old-secret');
  adoptBootstrapSecret(db, 'old-secret');

  assert.equal(await identify(req('Bearer old-secret'), { db }), LAN_USER);
  assert.equal(listTokens(db, LAN_USER).length, 1, 'restarting must not pile up tokens');
  assert.equal(sync(db, LAN_USER, 0, {}).changes.tasks[0].text, 'from before tokens');
});

test('changing the bootstrap secret retires the previous one', async () => {
  const db = freshDb();
  adoptBootstrapSecret(db, 'old-secret');
  const device = issueToken(db, LAN_USER, 'phone');

  adoptBootstrapSecret(db, 'new-secret');

  assert.equal(await identify(req('Bearer new-secret'), { db }), LAN_USER);
  // Otherwise "I changed TODO_SYNC_SECRET" would leave the old one opening the
  // door, which is the opposite of what changing it means.
  await assert.rejects(() => identify(req('Bearer old-secret'), { db }), AuthError);
  // Only the secret rotates. A token handed to a device is not collateral.
  assert.equal(resolveToken(db, device.token).userId, LAN_USER);
});

test('the owner and a new user coexist on a server that predates users', async () => {
  const db = freshDb();

  // Existing data, existing secret.
  sync(db, LAN_USER, 0, { tasks: [task('t-old', 'the owner\'s task', '2026-01-01T09:00:00Z')] });
  adoptBootstrapSecret(db, 'owner-secret');

  // The new arrival.
  const alice = createUser(db, 'Alice');
  const { token } = issueToken(db, alice.id, 'phone');
  sync(db, await identify(req(`Bearer ${token}`), { db }), 0, {
    tasks: [task('t-new', 'alice\'s task', '2026-08-03T10:00:00+02:00')],
  });

  const owner = sync(db, await identify(req('Bearer owner-secret'), { db }), 0, {});
  assert.deepEqual(owner.changes.tasks.map((t) => t.uuid), ['t-old']);

  const users = listUsers(db).map((u) => u.id);
  assert.deepEqual(users.sort(), [LAN_USER, alice.id].sort());
});

test('a fresh account starts empty rather than inheriting anything', async () => {
  const db = freshDb();
  sync(db, LAN_USER, 0, {
    tasks: [task('t-old', 'owner', '2026-01-01T09:00:00Z')],
    side_thoughts: [
      {
        uuid: 'st-1',
        text: 'owner thought',
        created_at: '2026-01-01T09:00:00Z',
        resolved_at: null,
        updated_at: '2026-01-01T09:00:00Z',
      },
    ],
  });

  const alice = createUser(db, 'Alice');
  const { cursor, changes } = sync(db, alice.id, 0, {});

  assert.equal(cursor, 0, 'nothing of theirs exists yet');
  for (const [table, rows] of Object.entries(changes)) {
    assert.equal(rows.length, 0, `${table} leaked into a new account`);
  }
});

test('issuing a token for an unknown user is refused', async () => {
  const db = freshDb();
  // Otherwise a typo in `--user` would mint a working token for an account
  // nobody can ever administer, holding rows no listing shows.
  assert.throws(() => issueToken(db, 'nobody-0000', 'phone'), /no such user/);
});

test('whoever holds the bootstrap secret is the admin', async () => {
  const db = freshDb();
  adoptBootstrapSecret(db, 'owner-secret');

  // The secret is printed on the server's own console, so holding it means
  // standing at the machine - which is what "operator" means here.
  assert.equal(isAdmin(db, LAN_USER), true);
  // Someone the admin invites is not one.
  assert.equal(isAdmin(db, createUser(db, 'Alice').id), false);
});

test('a local user created before admin existed gains it on the next start', async () => {
  const db = freshDb();
  // The shape the first multi-user build left behind: a local user, no admin.
  db.prepare('UPDATE users SET is_admin = 0 WHERE id = ?').run(
    adoptBootstrapSecret(db, 'owner-secret')
  );
  assert.equal(isAdmin(db, LAN_USER), false);

  adoptBootstrapSecret(db, 'owner-secret');
  assert.equal(isAdmin(db, LAN_USER), true, 'a restart must not leave the server admin-less');
});

test('admin can be granted and dropped, but never to nobody', async () => {
  const db = freshDb();
  adoptBootstrapSecret(db, 'owner-secret');
  const alice = createUser(db, 'Alice');

  setAdmin(db, alice.id, true);
  assert.equal(isAdmin(db, alice.id), true);

  setAdmin(db, LAN_USER, false);
  assert.equal(isAdmin(db, LAN_USER), false);

  // Alice is now the only admin. Dropping her would leave a server that cannot
  // be administered from any app, only from the machine it runs on.
  assert.throws(() => setAdmin(db, alice.id, false), /only admin/);
  assert.equal(isAdmin(db, alice.id), true);
});

test('deleting a user takes their rows with them', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const bob = createUser(db, 'Bob');
  issueToken(db, alice.id, 'phone');

  sync(db, alice.id, 0, {
    tasks: [task('t-a', 'alice', '2026-08-03T10:00:00+02:00')],
    side_thoughts: [
      {
        uuid: 'st-a',
        text: 'alice thought',
        created_at: '2026-08-03T10:00:00+02:00',
        resolved_at: null,
        updated_at: '2026-08-03T10:00:00+02:00',
      },
    ],
  });
  sync(db, bob.id, 0, { tasks: [task('t-b', 'bob', '2026-08-03T10:00:00+02:00')] });

  const removed = purgeUser(db, alice.id);
  assert.ok(removed >= 2, 'both of her rows were counted');

  // Gone from the listing, gone from the data, and her tokens with her.
  assert.deepEqual(listUsers(db).map((u) => u.id), [bob.id]);
  assert.equal(listTokens(db, alice.id).length, 0);
  const leftovers = sync(db, alice.id, 0, {});
  for (const [table, rows] of Object.entries(leftovers.changes)) {
    assert.equal(rows.length, 0, `${table} still held rows for a deleted user`);
  }
  // And the neighbour is untouched, which is the whole point of the scoping.
  assert.equal(sync(db, bob.id, 0, {}).changes.tasks[0].text, 'bob');
});

test('a deleted user\'s token stops working immediately', async () => {
  const db = freshDb();
  const alice = createUser(db, 'Alice');
  const { token } = issueToken(db, alice.id, 'phone');

  purgeUser(db, alice.id);
  // Not merely "their data is gone" - the credential must not still resolve,
  // or the next sync would silently recreate the account from its own rows.
  assert.equal(resolveToken(db, token), null);
  await assert.rejects(() => identify(req(`Bearer ${token}`), { db }), AuthError);
});

test('user ids are unique even for the same label', async () => {
  const db = freshDb();
  const first = createUser(db, 'Alice');
  const second = createUser(db, 'Alice');

  assert.notEqual(first.id, second.id);
  assert.match(first.id, /^alice-[0-9a-f]{4}$/);
});
