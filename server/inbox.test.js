// The inbox routes' writes (inbox.js): a thought or a todo from outside the
// app arrives as a row every device pulls, built the way the app builds it.

import test from 'node:test';
import assert from 'node:assert/strict';

import { openDb, sync } from './db.js';
import { identify, AuthError } from './auth.js';
import { InboxError, addThought, addTodo, readRemindAt, stampOf } from './inbox.js';
import { INBOX_SCOPE, NOTIFY_SCOPE, createUser, issueToken } from './users.js';

const USER = 'u1';
const STAMP = '2026-10-01T10:00:00.000+02:00';

function workspace(uuid, name, extra = {}) {
  return {
    uuid,
    name,
    color: '#88aaff',
    sort_order: 0,
    shortcuts: null,
    parent_uuid: null,
    archived_at: null,
    created_at: STAMP,
    updated_at: STAMP,
    deleted_at: null,
    ...extra,
  };
}

function seeded() {
  const db = openDb(':memory:');
  sync(db, USER, 0, {
    workspaces: [
      workspace('ws-home', 'Home', { sort_order: 0 }),
      workspace('ws-work', 'Work', { sort_order: 1, shortcuts: '["job"]' }),
      workspace('ws-proj', 'Rewrite', { parent_uuid: 'ws-work', sort_order: 4 }),
      workspace('ws-old', 'Old', { sort_order: 2, archived_at: STAMP }),
    ],
    parked_groups: [
      {
        uuid: 'g-ideas',
        workspace_uuid: 'ws-work',
        title: 'Ideas',
        sort_order: 0,
        created_at: STAMP,
        updated_at: STAMP,
      },
    ],
    tasks: [
      {
        uuid: 't-1',
        workspace_uuid: 'ws-work',
        text: 'already there',
        created_at: STAMP,
        sort_order: 2,
        in_progress: 0,
        notes: '',
        priority: 0,
        updated_at: STAMP,
      },
    ],
  });
  return db;
}

/** What a device would pull now, from scratch. */
const pulled = (db, table) => sync(db, USER, 0, {}).changes[table];

test('a thought lands in the pile, and a device pulls it', () => {
  const db = seeded();
  const { result, notification } = addThought(db, USER, { text: '  disk at 85%  ' });

  assert.equal(result.text, 'disk at 85%');
  assert.equal(notification, null, 'no push unless asked');
  const row = pulled(db, 'side_thoughts').find((t) => t.uuid === result.id);
  assert.equal(row.text, 'disk at 85%');
  assert.equal(row.resolved_at, null);
  assert.match(row.created_at, /[+-]\d{2}:\d{2}$/, 'a stamp with its offset, as the app writes');
});

test('notify: true asks for a push saying the same thing', () => {
  const db = seeded();
  const { notification } = addThought(db, USER, { text: 'deploy done', notify: true });
  assert.deepEqual(notification, { title: 'Thought', body: 'deploy done', url: '/' });
});

test('a todo goes to the first workspace unless one is named', () => {
  const db = seeded();
  const { result } = addTodo(db, USER, { text: 'renew the cert' });
  assert.equal(result.workspace, 'Home');
  const row = pulled(db, 'tasks').find((t) => t.uuid === result.id);
  assert.equal(row.workspace_uuid, 'ws-home');
  assert.equal(row.completed_at, null);
  assert.equal(row.group_uuid, null);
  assert.equal(row.notes, '');
  assert.equal(row.priority, 0);
});

test('a workspace is found by name or shortcut, ignoring case', () => {
  const db = seeded();
  assert.equal(addTodo(db, USER, { text: 'a', workspace: 'work' }).result.workspace, 'Work');
  assert.equal(addTodo(db, USER, { text: 'b', workspace: '#JOB' }).result.workspace, 'Work');
  assert.equal(addTodo(db, USER, { text: 'c', workspace: 'rewrite' }).result.workspace, 'Rewrite');
});

test('a todo lands after everything on its list, projects included', () => {
  const db = seeded();
  const { result } = addTodo(db, USER, { title: 'last', workspace: 'Work' });
  const row = pulled(db, 'tasks').find((t) => t.uuid === result.id);
  assert.equal(row.sort_order, 5, 'after the project at 4, not the task at 2');
});

test('a shelf, notes, priority and a reminder are carried', () => {
  const db = seeded();
  const { result, notification } = addTodo(db, USER, {
    text: 'look at the logs',
    workspace: 'Work',
    shelf: 'ideas',
    notes: '**3** errors',
    high_priority: true,
    remind_at: '2026-11-02T09:00:00+01:00',
    notify: true,
  });
  const row = pulled(db, 'tasks').find((t) => t.uuid === result.id);
  assert.equal(row.group_uuid, 'g-ideas');
  assert.equal(row.notes, '**3** errors');
  assert.equal(row.priority, 1);
  assert.equal(row.remind_at, '2026-11-02T08:00:00.000Z', 'a UTC instant, like reminderStamp');
  assert.equal(result.shelf, 'Ideas');
  assert.equal(notification.title, 'Work · Ideas');
});

test('a miss says what there is', () => {
  const db = seeded();
  assert.throws(
    () => addTodo(db, USER, { text: 'x', workspace: 'Old' }),
    (err) =>
      err instanceof InboxError &&
      /No workspace called "Old"/.test(err.message) &&
      !err.extra.workspaces.includes('Old') &&
      err.extra.workspaces.includes('Work')
  );
  assert.throws(
    () => addTodo(db, USER, { text: 'x', workspace: 'Work', shelf: 'Someday' }),
    (err) => err instanceof InboxError && err.extra.shelves.includes('Ideas')
  );
});

test('an account with no workspace is told to make one', () => {
  const db = openDb(':memory:');
  assert.throws(() => addTodo(db, USER, { text: 'x' }), /no workspace yet/);
  // A thought needs none: the pile is global.
  assert.ok(addThought(db, USER, { text: 'x' }).result.id);
});

test('bad requests are refused, not half-written', () => {
  const db = seeded();
  const before = pulled(db, 'tasks').length;
  for (const input of [
    null,
    [],
    {},
    { text: '   ' },
    { text: 42 },
    { text: 'x'.repeat(2001) },
    { text: 'x', notify: 'yes' },
    { text: 'x', remind_at: '2026-11-02T09:00' },
    { text: 'x', workspace: 7 },
  ]) {
    assert.throws(() => addTodo(db, USER, input), InboxError, JSON.stringify(input));
  }
  assert.equal(pulled(db, 'tasks').length, before);
});

test('remind_at must say its timezone', () => {
  assert.equal(readRemindAt('2026-11-02T08:00:00Z'), '2026-11-02T08:00:00.000Z');
  assert.equal(readRemindAt('2026-11-02T09:30:00+0100'), '2026-11-02T08:30:00.000Z');
  assert.equal(readRemindAt(null), null);
  assert.throws(() => readRemindAt('tomorrow'), InboxError);
  assert.throws(() => readRemindAt('2026-11-02 09:00'), InboxError);
});

test('stampOf writes the local reading and its offset', () => {
  const at = new Date(2026, 0, 5, 7, 8, 9, 10);
  assert.match(stampOf(at), /^2026-01-05T07:08:09\.010[+-]\d{2}:\d{2}$/);
  assert.equal(Date.parse(stampOf(at)), at.getTime());
});

test('an inbox token is good for the inbox and notify, and nothing else', async () => {
  const db = openDb(':memory:');
  const alice = createUser(db, 'Alice');
  const { token } = issueToken(db, alice.id, 'backup script', { scope: INBOX_SCOPE });
  const req = { get: () => `Bearer ${token}` };

  assert.equal(await identify(req, { db }, { scope: INBOX_SCOPE }), alice.id);
  assert.equal(await identify(req, { db }, { scope: [NOTIFY_SCOPE, INBOX_SCOPE] }), alice.id);
  // Sync, the feed, the blobs: every ordinary route asks for no scope.
  await assert.rejects(
    () => identify(req, { db }),
    (err) => err instanceof AuthError && err.status === 403
  );
  // And a notify-only token does not reach the inbox.
  const hook = issueToken(db, alice.id, 'beszel', { scope: NOTIFY_SCOPE });
  await assert.rejects(
    () => identify({ get: () => `Bearer ${hook.token}` }, { db }, { scope: INBOX_SCOPE }),
    (err) => err instanceof AuthError && err.status === 403
  );
});
