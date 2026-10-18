// Web Push reminders. Run with: npm run test:server
//
// What is under test is *which* notifications go out and how often - the
// push services themselves are replaced by a recording `send`, because a real
// one needs a real browser at the other end. The timezone is pinned below so
// the DST case crosses a real boundary on any machine.

import test from 'node:test';
import assert from 'node:assert/strict';

import { openDb, purgeUser, sync } from './db.js';
import {
  dueNotifications,
  eventLead,
  notifyUser,
  nth,
  NOTIFY_BODY_MAX,
  readNotification,
  readSubscription,
  saveSubscription,
  subscriptionsOf,
  tick,
  vapidKeys,
} from './push.js';

// Node reads TZ when a Date is made, so setting it here is in time.
process.env.TZ = 'Europe/Berlin';

const USER = 'local';
const STAMP = '2026-10-01T10:00:00+02:00';

function task(uuid, text, remind_at, extra = {}) {
  return {
    uuid,
    workspace_uuid: 'ws-1',
    text,
    created_at: STAMP,
    completed_at: null,
    sort_order: 0,
    in_progress: 0,
    remind_at,
    updated_at: STAMP,
    deleted_at: null,
    ...extra,
  };
}

function event(uuid, start_at, end_at, extra = {}) {
  return {
    uuid,
    calendar_uuid: 'cal-1',
    title: `event ${uuid}`,
    description: '',
    start_at,
    end_at,
    notify_minutes: null,
    recur: null,
    all_day: 0,
    created_at: STAMP,
    updated_at: STAMP,
    deleted_at: null,
    ...extra,
  };
}

function calendar(notify_minutes) {
  return {
    uuid: 'cal-1',
    workspace_uuid: 'ws-1',
    name: 'Work',
    color: '#888',
    notify_minutes,
    sort_order: 0,
    created_at: STAMP,
    updated_at: STAMP,
    deleted_at: null,
  };
}

const SUB = {
  endpoint: 'https://push.example.com/abc',
  keys: { p256dh: 'p'.repeat(40), auth: 'a'.repeat(16) },
};

function subscribed() {
  const db = openDb(':memory:');
  saveSubscription(db, USER, readSubscription(SUB), 'https://todo.example.com');
  return db;
}

/** A `send` that records instead of delivering. */
function recorder(fail) {
  const sent = [];
  const send = async (sub, payload) => {
    if (fail) throw fail;
    sent.push({ endpoint: sub.endpoint, ...JSON.parse(payload) });
  };
  return { sent, send };
}

const at = (s) => new Date(s);

test('a task reminder in the window is due; parked, done and future ones are not', () => {
  const db = subscribed();
  sync(db, USER, 0, {
    tasks: [
      task('due', 'call the bank', '2026-10-10T09:00:00+02:00'),
      task('later', 'not yet', '2026-10-10T12:00:00+02:00'),
      task('parked', 'on a shelf', '2026-10-10T09:00:00+02:00', { group_uuid: 'g' }),
      task('done', 'finished', '2026-10-10T09:00:00+02:00', { completed_at: STAMP }),
    ],
  });
  const due = dueNotifications(db, USER, at('2026-10-10T06:55:00Z'), at('2026-10-10T07:05:00Z'));
  assert.deepEqual(due.map((n) => n.body), ['call the bank']);
  assert.equal(due[0].title, 'Reminder');
});

test('a task in an archived project is quiet', () => {
  const db = subscribed();
  const ws = (uuid, archived_at) => ({
    uuid,
    name: uuid,
    color: '#888',
    sort_order: 0,
    parent_uuid: 'ws-1',
    archived_at,
    created_at: STAMP,
    updated_at: STAMP,
    deleted_at: null,
  });
  sync(
    db,
    USER,
    0,
    {
      workspaces: [ws('p-open', null), ws('p-shut', STAMP)],
      tasks: [
        task('live', 'in a project', '2026-10-10T09:00:00+02:00', { workspace_uuid: 'p-open' }),
        task('shut', 'archived', '2026-10-10T09:00:00+02:00', { workspace_uuid: 'p-shut' }),
      ],
    },
    7
  );
  const due = dueNotifications(db, USER, at('2026-10-10T06:55:00Z'), at('2026-10-10T07:05:00Z'));
  assert.deepEqual(due.map((n) => n.body), ['in a project']);
});

test('stamps are compared as instants, whatever offset wrote them', () => {
  const db = subscribed();
  // 03:00 in New York is 07:00Z - inside the window although its text sorts
  // nowhere near the Berlin-written bounds.
  sync(db, USER, 0, { tasks: [task('ny', 'from a trip', '2026-10-10T03:00:00-04:00')] });
  const due = dueNotifications(db, USER, at('2026-10-10T06:55:00Z'), at('2026-10-10T07:05:00Z'));
  assert.equal(due.length, 1);
});

test('an event fires its lead before the start, inheriting the calendar', () => {
  const db = subscribed();
  sync(db, USER, 0, {
    calendars: [calendar(15)],
    calendar_events: [event('e', '2026-10-10T08:00:00.000Z', '2026-10-10T09:00:00.000Z')],
  });
  const due = dueNotifications(db, USER, at('2026-10-10T07:40:00Z'), at('2026-10-10T07:50:00Z'));
  assert.equal(due.length, 1);
  assert.equal(due[0].at.toISOString(), '2026-10-10T07:45:00.000Z');
  assert.match(due[0].body, /^\d\d:\d\d – \d\d:\d\d$/);
});

test('lead rules match the app: -1 is silent, all-day does not inherit', () => {
  assert.equal(eventLead({ notify_minutes: -1 }, { notify_minutes: 10 }), null);
  assert.equal(eventLead({ notify_minutes: null, all_day: 1 }, { notify_minutes: 60 }), null);
  assert.equal(eventLead({ notify_minutes: 30, all_day: 1 }, { notify_minutes: 60 }), 30);
  assert.equal(eventLead({ notify_minutes: null }, { notify_minutes: 5 }), 5);
  assert.equal(eventLead({ notify_minutes: null }, undefined), null);
});

test('a repeating event fires on a later occurrence', () => {
  const db = subscribed();
  sync(db, USER, 0, {
    calendars: [calendar(0)],
    calendar_events: [
      event('daily', '2026-01-05T08:00:00.000Z', '2026-01-05T08:30:00.000Z', { recur: 'daily' }),
    ],
  });
  // 09:00 Berlin winter time is 08:00Z in January and 07:00Z in October.
  const due = dueNotifications(db, USER, at('2026-10-10T06:55:00Z'), at('2026-10-10T07:05:00Z'));
  assert.equal(due.length, 1, 'still 09:00 local after the DST change');
  assert.equal(due[0].key, 'event:daily:2026-10-10T07:00:00.000Z');
});

test('nth counts from the anchor: monthly on the 31st keeps the 31st', () => {
  const anchor = new Date(2026, 0, 31, 9, 0);
  assert.equal(nth(anchor, 'monthly', 1).getDate(), 28);
  assert.equal(nth(anchor, 'monthly', 2).getDate(), 31);
  // Weekdays from a Friday: Monday next.
  const friday = new Date(2026, 9, 9, 9, 0);
  assert.equal(nth(friday, 'weekdays', 1).getDay(), 1);
  assert.equal(nth(friday, 'unknown', 1), null);
});

test('a tick sends each reminder once, however often it looks', async () => {
  const db = subscribed();
  const keys = vapidKeys(db);
  sync(db, USER, 0, { tasks: [task('t', 'water the plants', '2026-10-10T09:00:00+02:00')] });
  const { sent, send } = recorder();

  assert.equal(await tick(db, keys, at('2026-10-10T07:00:30Z'), { send }), 1);
  assert.equal(await tick(db, keys, at('2026-10-10T07:01:30Z'), { send }), 0);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].body, 'water the plants');
  assert.equal(sent[0].endpoint, SUB.endpoint);
});

test('moving a reminder makes it a new one', async () => {
  const db = subscribed();
  const keys = vapidKeys(db);
  const { sent, send } = recorder();
  sync(db, USER, 0, { tasks: [task('t', 'stretch', '2026-10-10T09:00:00+02:00')] });
  await tick(db, keys, at('2026-10-10T07:00:30Z'), { send });
  sync(db, USER, 0, {
    tasks: [task('t', 'stretch', '2026-10-10T09:05:00+02:00', { updated_at: '2026-10-10T09:01:00+02:00' })],
  });
  await tick(db, keys, at('2026-10-10T07:05:30Z'), { send });
  assert.equal(sent.length, 2);
});

test('an endpoint the push service says is gone is dropped', async () => {
  const db = subscribed();
  const keys = vapidKeys(db);
  sync(db, USER, 0, { tasks: [task('t', 'x', '2026-10-10T09:00:00+02:00')] });
  const { send } = recorder(Object.assign(new Error('gone'), { statusCode: 410 }));
  await tick(db, keys, at('2026-10-10T07:00:30Z'), { send });
  assert.equal(subscriptionsOf(db, USER).length, 0);
});

test('only https endpoints with both keys are accepted', () => {
  assert.ok(readSubscription(SUB));
  assert.equal(readSubscription({ ...SUB, endpoint: 'http://push.example.com/x' }), null);
  assert.equal(readSubscription({ ...SUB, endpoint: 'not a url' }), null);
  assert.equal(readSubscription({ endpoint: SUB.endpoint, keys: { auth: 'a' } }), null);
});

test('the VAPID pair is made once and kept', () => {
  const db = openDb(':memory:');
  assert.deepEqual(vapidKeys(db), vapidKeys(db));
});

test('deleting an account removes its subscriptions', () => {
  const db = subscribed();
  purgeUser(db, USER);
  assert.equal(subscriptionsOf(db, USER).length, 0);
});

test('a notification reads title and body, or message for body', () => {
  assert.deepEqual(readNotification({ title: 'Disk', body: '85% full' }), {
    title: 'Disk',
    body: '85% full',
    url: '/',
  });
  // What webhook senders (Beszel's included) call the text.
  assert.equal(readNotification({ title: 'Disk', message: '85% full' }).body, '85% full');
  assert.equal(readNotification({ body: 'no title' }).title, 'Todo');
  assert.equal(readNotification({ title: 'x', tag: 'disk' }).tag, 'disk');
});

test('a notification with nothing to say, or the wrong types, is refused', () => {
  assert.equal(readNotification(null), null);
  assert.equal(readNotification('text'), null);
  assert.equal(readNotification({}), null);
  assert.equal(readNotification({ title: '  ', body: '' }), null);
  assert.equal(readNotification({ title: 5 }), null);
  assert.equal(readNotification({ title: 'x', tag: 'y'.repeat(65) }), null);
});

test('a long notification is cut, not refused', () => {
  const n = readNotification({ title: 'x', body: 'y'.repeat(5000) });
  assert.equal(n.body.length, NOTIFY_BODY_MAX);
  assert.ok(n.body.endsWith('…'));
});

test('a notification goes to every subscription of that user, and no one else', async () => {
  const db = subscribed();
  saveSubscription(db, USER, readSubscription({ ...SUB, endpoint: 'https://push.example.com/laptop' }));
  saveSubscription(db, 'someone-else', readSubscription({ ...SUB, endpoint: 'https://push.example.com/bob' }));
  const { sent, send } = recorder();

  const result = await notifyUser(db, vapidKeys(db), USER, readNotification({ title: 'Disk', body: '85%' }), { send });
  assert.deepEqual(result, { sent: 2, subscriptions: 2 });
  assert.deepEqual(sent.map((s) => s.endpoint).sort(), [SUB.endpoint, 'https://push.example.com/laptop']);
  assert.equal(sent[0].title, 'Disk');
});

test('a notification to a user with no subscriptions sends nothing', async () => {
  const db = openDb(':memory:');
  const { send } = recorder();
  assert.deepEqual(await notifyUser(db, vapidKeys(db), USER, { title: 'x' }, { send }), {
    sent: 0,
    subscriptions: 0,
  });
});
