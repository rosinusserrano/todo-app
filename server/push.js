// Web Push: reminders for the browser build, sent by the server.
//
// The native apps hand their reminders to the OS ahead of time
// (notifications.dart). A browser cannot: a page that is not open runs no
// code, and a home-screen web app on an iPhone is not open most of the day.
// What it *can* do is receive a push, and a push has to come from somewhere
// that is awake - which is this server, the one thing that already holds every
// task and calendar row.
//
// The shape:
//
//   subscriptions  one row per browser that said yes, keyed by its endpoint
//                  (the push service's URL for that browser). A user can have
//                  several - a phone and a laptop - and each gets every push.
//   the tick       once a minute, for each user with a subscription, work out
//                  which reminders fell due since the last look and send them.
//                  Reminders are read from the synced rows, so a reminder set
//                  on the desktop reaches the phone's web app with no extra
//                  write path - the same reason the native side reconciles
//                  from a query rather than hooking writes.
//   push_sent      what has already gone out, keyed by row *and* instant, so a
//                  restart or two overlapping ticks never send one twice, and
//                  moving a reminder to a new time is a new reminder.
//
// Three rules mirror the client's, because a server that notified differently
// from the native app would be a second definition of "a reminder":
//
//   - A parked task does not fire (`group_uuid` set): parking means "not now".
//   - Nor does a task in an archived project (`workspaces.archived_at`): the
//     archive is a project put away whole, open tasks and all.
//   - An event's lead is its own `notify_minutes`, else its calendar's; -1 is
//     silent; an all-day event does not inherit the calendar's lead (an hour
//     before midnight is 23:00 the night before every birthday).
//   - A repeating event is one row, and its occurrences are counted from the
//     anchor in **local time** (`nth`, a port of `Recur.nth`), so a 09:00 block
//     stays at 09:00 across a DST change. "Local" is this process's timezone -
//     set TZ in the service environment if the server is not where you are.
//
// What it does not do: write anything users see. A rule-based repeating task
// spawns its next occurrence on a device (the reminder poll); with no device
// running, the server sees no new row and has nothing to remind about.
//
// The VAPID key pair is made on first start and kept in `meta`. It is what the
// push services check a sender against, and every subscription is bound to the
// public half - change it and every browser has to subscribe again.

import webpush from 'web-push';

/** How far back a tick looks. Covers a restart or a missed tick; push_sent
 *  keeps a wider window from ever sending the same reminder twice. */
export const LOOKBACK_MS = 10 * 60 * 1000;

const EVENT_RULES = ['daily', 'weekdays', 'weekly', 'monthly', 'yearly'];

export function initPush(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS push_subscriptions (
      endpoint    TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      p256dh      TEXT NOT NULL,
      auth        TEXT NOT NULL,
      -- Who the push services should contact about this sender: the address
      -- the page was served from, unless TODO_PUSH_SUBJECT says otherwise.
      subject     TEXT,
      created_at  TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user
      ON push_subscriptions (user_id);

    CREATE TABLE IF NOT EXISTS push_sent (
      user_id  TEXT NOT NULL,
      key      TEXT NOT NULL,
      sent_at  TEXT NOT NULL,
      PRIMARY KEY (user_id, key)
    );
  `);
}

/** For purgeUser: an account that is gone gets no more pushes. */
export function deletePushFor(db, userId) {
  db.prepare('DELETE FROM push_subscriptions WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM push_sent WHERE user_id = ?').run(userId);
}

/** The server's VAPID pair, made once and kept. */
export function vapidKeys(db) {
  const get = (k) => db.prepare('SELECT value FROM meta WHERE key = ?').get(k)?.value;
  let publicKey = get('vapid_public');
  let privateKey = get('vapid_private');
  if (!publicKey || !privateKey) {
    ({ publicKey, privateKey } = webpush.generateVAPIDKeys());
    const put = db.prepare('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)');
    db.transaction(() => {
      put.run('vapid_public', publicKey);
      put.run('vapid_private', privateKey);
    })();
  }
  return { publicKey, privateKey };
}

// --------------------------------------------------------------- subscriptions

/** Null when the body is not a usable subscription, else the parts to store. */
export function readSubscription(body) {
  if (typeof body !== 'object' || body === null) return null;
  const { endpoint, keys } = body;
  if (typeof endpoint !== 'string' || endpoint.length > 2048) return null;
  let url;
  try {
    url = new URL(endpoint);
  } catch {
    return null;
  }
  // Every push service is https; anything else is not a push endpoint and
  // would have this server POSTing to wherever it pointed.
  if (url.protocol !== 'https:') return null;
  if (typeof keys !== 'object' || keys === null) return null;
  const { p256dh, auth } = keys;
  const ok = (s) => typeof s === 'string' && s.length > 0 && s.length <= 256;
  if (!ok(p256dh) || !ok(auth)) return null;
  return { endpoint, p256dh, auth };
}

/**
 * Store or refresh a subscription. An endpoint is one browser, so if it was
 * someone else's (a shared laptop that changed accounts) it moves to this user
 * rather than pushing one account's reminders to another's session.
 */
export function saveSubscription(db, userId, sub, subject, now = new Date()) {
  db.prepare(
    `INSERT INTO push_subscriptions (endpoint, user_id, p256dh, auth, subject, created_at)
     VALUES (@endpoint, @userId, @p256dh, @auth, @subject, @at)
     ON CONFLICT (endpoint) DO UPDATE SET
       user_id = excluded.user_id, p256dh = excluded.p256dh,
       auth = excluded.auth, subject = excluded.subject`
  ).run({ ...sub, userId, subject: subject ?? null, at: now.toISOString() });
}

/** Only the owner can remove one; returns whether anything was removed. */
export function deleteSubscription(db, userId, endpoint) {
  return (
    db
      .prepare('DELETE FROM push_subscriptions WHERE endpoint = ? AND user_id = ?')
      .run(endpoint, userId).changes > 0
  );
}

export function subscriptionsOf(db, userId) {
  return db.prepare('SELECT * FROM push_subscriptions WHERE user_id = ?').all(userId);
}

// ----------------------------------------------------------------- what is due

/**
 * The occurrence [n] steps after [anchor], counted from the anchor in local
 * time. A port of `Recur.nth` in models.dart - keep the two in step. Null for
 * a rule this does not know, which then reads as a one-off.
 */
export function nth(anchor, rule, n) {
  const a = anchor;
  const at = (y, m, d) =>
    new Date(y, m, d, a.getHours(), a.getMinutes(), a.getSeconds());
  const lastDay = (y, m) => new Date(y, m + 1, 0).getDate();

  switch (rule) {
    case 'daily':
      return at(a.getFullYear(), a.getMonth(), a.getDate() + n);
    case 'weekly':
      return at(a.getFullYear(), a.getMonth(), a.getDate() + 7 * n);
    case 'weekdays': {
      let first = a;
      while (first.getDay() === 0 || first.getDay() === 6) {
        first = at(first.getFullYear(), first.getMonth(), first.getDate() + 1);
      }
      const w = first.getDay() - 1; // Monday 0 .. Friday 4
      const idx = w + n;
      const days = Math.floor(idx / 5) * 7 + (idx % 5) - w;
      return at(first.getFullYear(), first.getMonth(), first.getDate() + days);
    }
    case 'monthly': {
      const month = a.getMonth() + n;
      const y = a.getFullYear() + Math.floor(month / 12);
      const m = month % 12;
      return at(y, m, Math.min(a.getDate(), lastDay(y, m)));
    }
    case 'yearly': {
      const y = a.getFullYear() + n;
      return at(y, a.getMonth(), Math.min(a.getDate(), lastDay(y, a.getMonth())));
    }
  }
  return null;
}

/** Steps to skip before looking, so a daily block from 2019 is not walked
 *  from 2019 every minute. Deliberately an underestimate. */
function firstStep(anchor, rule, from) {
  const days = (from - anchor) / 86_400_000;
  if (days <= 0) return 0;
  const guess = {
    daily: days,
    weekly: days / 7,
    weekdays: (days / 7) * 5,
    monthly: days / 31,
    yearly: days / 366,
  }[rule];
  return Math.max(0, Math.floor(guess ?? 0) - 2);
}

/** Starts of the occurrences of a stored event that begin in (from, to]. */
function startsIn(ev, from, to) {
  const anchor = new Date(ev.start_at);
  if (Number.isNaN(anchor.getTime())) return [];
  const rule = EVENT_RULES.includes(ev.recur) ? ev.recur : null;
  if (!rule) return anchor > from && anchor <= to ? [anchor] : [];

  const out = [];
  for (let n = firstStep(anchor, rule, from), i = 0; i < 1000; n++, i++) {
    const at = n === 0 ? anchor : nth(anchor, rule, n);
    if (!at || at > to) break;
    if (at > from) out.push(at);
  }
  return out;
}

/** An event's resolved lead in minutes, or null for silent. Mirrors
 *  `CalendarEvent.notifyLead`. */
export function eventLead(ev, calendar) {
  const own = ev.notify_minutes;
  if (own === -1) return null;
  if (ev.all_day && own == null) return null;
  const minutes = own ?? calendar?.notify_minutes;
  if (minutes == null || minutes < 0) return null;
  return minutes;
}

const hhmm = (d) =>
  `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;

/**
 * Everything that should notify in (from, to], oldest first, as the payloads
 * to send. Pure over the database, so the tests need no clock and no network.
 */
export function dueNotifications(db, userId, from, to) {
  const out = [];

  const tasks = db
    .prepare(
      `SELECT uuid, text, remind_at FROM tasks
       WHERE user_id = ? AND remind_at IS NOT NULL AND completed_at IS NULL
         AND deleted_at IS NULL AND group_uuid IS NULL
         AND workspace_uuid NOT IN (
           SELECT uuid FROM workspaces
           WHERE user_id = tasks.user_id AND archived_at IS NOT NULL
         )`
    )
    .all(userId);
  for (const t of tasks) {
    // Parsed rather than compared as text: the stamps carry the offset of
    // whichever device wrote them, and text order is only time order when the
    // offsets agree.
    const at = new Date(t.remind_at);
    if (Number.isNaN(at.getTime()) || !(at > from && at <= to)) continue;
    out.push({
      at,
      key: `task:${t.uuid}:${t.remind_at}`,
      title: 'Reminder',
      body: t.text,
    });
  }

  const calendars = new Map(
    db
      .prepare('SELECT uuid, notify_minutes, deleted_at FROM calendars WHERE user_id = ?')
      .all(userId)
      .map((c) => [c.uuid, c])
  );
  const events = db
    .prepare(
      `SELECT uuid, calendar_uuid, title, description, start_at, end_at,
              notify_minutes, recur, all_day
       FROM calendar_events WHERE user_id = ? AND deleted_at IS NULL`
    )
    .all(userId);
  for (const ev of events) {
    const calendar = calendars.get(ev.calendar_uuid);
    if (calendar?.deleted_at) continue;
    const lead = eventLead(ev, calendar);
    if (lead == null) continue;
    const leadMs = lead * 60_000;
    const length = new Date(ev.end_at) - new Date(ev.start_at);
    // Fires in (from, to] means starts in (from + lead, to + lead].
    for (const start of startsIn(
      ev,
      new Date(from.getTime() + leadMs),
      new Date(to.getTime() + leadMs)
    )) {
      const end = new Date(start.getTime() + (Number.isFinite(length) ? length : 0));
      const when = ev.all_day ? 'All day' : `${hhmm(start)} – ${hhmm(end)}`;
      out.push({
        at: new Date(start.getTime() - leadMs),
        key: `event:${ev.uuid}:${start.toISOString()}`,
        title: ev.title,
        body: ev.description ? `${when} · ${ev.description}` : when,
      });
    }
  }

  out.sort((a, b) => a.at - b.at);
  return out;
}

/** Records the key and says whether it was new - the one place "send it
 *  once" is decided, and atomic, so two ticks cannot both claim it. */
function claim(db, userId, key, now) {
  return (
    db
      .prepare('INSERT OR IGNORE INTO push_sent (user_id, key, sent_at) VALUES (?, ?, ?)')
      .run(userId, key, now.toISOString()).changes > 0
  );
}

// ----------------------------------------------------------------- sending

/**
 * Sends a payload to one subscription. Resolves to 'ok', 'gone' (the browser
 * unsubscribed or the endpoint expired - the row is removed) or 'failed'.
 */
export async function sendTo(db, keys, sub, payload, { send = webpush.sendNotification } = {}) {
  const subject =
    process.env.TODO_PUSH_SUBJECT || sub.subject || 'mailto:todo-widget@localhost';
  try {
    await send(
      { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
      JSON.stringify(payload),
      {
        vapidDetails: { subject, publicKey: keys.publicKey, privateKey: keys.privateKey },
        // A reminder an hour late is no longer the reminder that was asked for.
        TTL: 3600,
        urgency: 'high',
      }
    );
    return 'ok';
  } catch (err) {
    if (err?.statusCode === 404 || err?.statusCode === 410) {
      db.prepare('DELETE FROM push_subscriptions WHERE endpoint = ?').run(sub.endpoint);
      return 'gone';
    }
    console.warn(`[push] ${sub.endpoint.slice(0, 48)}…: ${err?.statusCode ?? ''} ${err?.body ?? err}`);
    return 'failed';
  }
}

/**
 * One look: every user with a subscription, everything due in the lookback,
 * each sent once. Returns how many notifications went out, for the tests.
 */
export async function tick(db, keys, now = new Date(), opts = {}) {
  const from = new Date(now.getTime() - LOOKBACK_MS);
  const users = db.prepare('SELECT DISTINCT user_id FROM push_subscriptions').all();
  let sent = 0;
  for (const { user_id: userId } of users) {
    const due = dueNotifications(db, userId, from, now).filter((n) =>
      claim(db, userId, n.key, now)
    );
    if (due.length === 0) continue;
    const subs = subscriptionsOf(db, userId);
    for (const n of due) {
      const payload = { title: n.title, body: n.body, tag: n.key, url: '/' };
      for (const sub of subs) {
        if ((await sendTo(db, keys, sub, payload, opts)) === 'ok') sent++;
      }
    }
  }
  // A month of history is far more than the lookback needs and keeps the
  // table from growing for ever.
  db.prepare('DELETE FROM push_sent WHERE sent_at < ?').run(
    new Date(now.getTime() - 30 * 86_400_000).toISOString()
  );
  return sent;
}

// ------------------------------------------------------------- notifications
//
// The other way in: something outside the app - the server's monitoring, a
// backup script - has news for an account and calls POST /api/notify. It goes
// to every subscription of that account and is not recorded anywhere; whether
// to send the same news twice is the sender's business, not this server's.

/** Longest title and body kept. A push payload has to fit in ~4KB after
 *  encryption, and a lock screen shows far less than this anyway. */
export const NOTIFY_TITLE_MAX = 120;
export const NOTIFY_BODY_MAX = 600;

function clip(text, max) {
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`;
}

/**
 * The notification in a request body, or null when there is none to send.
 *
 * Takes `body` or `message` for the text - `message` is what most webhook
 * senders call it, Beszel's included, and refusing it would turn every one of
 * them into a 400 for a naming difference. Too-long text is cut, not refused:
 * an alert that arrives shortened beats one that never arrives.
 */
export function readNotification(input) {
  if (typeof input !== 'object' || input === null) return null;
  const text = (v) => (typeof v === 'string' ? v.trim() : v == null ? '' : null);
  const title = text(input.title);
  const body = text(input.body ?? input.message);
  if (title === null || body === null || (!title && !body)) return null;

  const tag = input.tag;
  if (tag != null && (typeof tag !== 'string' || !tag || tag.length > 64)) return null;

  return {
    title: clip(title || 'Todo', NOTIFY_TITLE_MAX),
    body: clip(body, NOTIFY_BODY_MAX),
    // Same tag replaces the earlier notification on the device; none stacks.
    ...(tag ? { tag } : {}),
    url: '/',
  };
}

/** Sends one notification to every subscription of a user. */
export async function notifyUser(db, keys, userId, payload, opts = {}) {
  const subs = subscriptionsOf(db, userId);
  let sent = 0;
  for (const sub of subs) {
    if ((await sendTo(db, keys, sub, payload, opts)) === 'ok') sent++;
  }
  return { sent, subscriptions: subs.length };
}

/** Starts the minute tick. Returns a stop function. */
export function startPush(db, { intervalMs = 60_000 } = {}) {
  const keys = vapidKeys(db);
  let running = false;
  const run = async () => {
    if (running) return; // a slow push service must not stack ticks
    running = true;
    try {
      await tick(db, keys);
    } catch (err) {
      console.error('[push] tick failed:', err);
    } finally {
      running = false;
    }
  };
  const timer = setInterval(run, intervalMs);
  timer.unref?.();
  run();
  return () => clearInterval(timer);
}
