// What each account has been doing to this server, by day - for the admin's
// overview in the app (Settings → Server traffic, `/api/admin/traffic`).
//
// Counters, not a log. One row per account per day, bumped as each
// authenticated request finishes: how many requests, how many of them were
// syncs, how many rows went each way and how many bytes. That answers "who is
// using this and how hard" without the server keeping a record of *what*
// anyone did, which nobody asked for and a log would be.
//
// Things that are load-bearing:
//
//   - **Recorded on `finish`, keyed on `req.userId`.** The middleware runs
//     ahead of every route, but the account is only known once a route's own
//     auth has run; reading it when the response is done is what lets one
//     `app.use` cover every authenticated route without each one opting in.
//     Unauthenticated requests (health, the web app's files) are nobody's.
//   - **A day is the server's local date.** The panel is read by the person
//     running the server, in its timezone.
//   - **Rows are counted by the sync route** (`res.locals.traffic`), the only
//     place that knows how many went each way. Bytes are the body lengths as
//     sent - what a metered connection would charge for, near enough.
//   - **Kept for `KEEP_DAYS`** and pruned once a day, so the table is bounded
//     by accounts x days and never by how busy anyone is.

export const KEEP_DAYS = 400;

export function initTraffic(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS traffic (
      user_id   TEXT NOT NULL,
      day       TEXT NOT NULL,
      requests  INTEGER NOT NULL DEFAULT 0,
      syncs     INTEGER NOT NULL DEFAULT 0,
      rows_in   INTEGER NOT NULL DEFAULT 0,
      rows_out  INTEGER NOT NULL DEFAULT 0,
      bytes_in  INTEGER NOT NULL DEFAULT 0,
      bytes_out INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (user_id, day)
    );
  `);
}

/** `YYYY-MM-DD` in the server's local time. */
export function dayOf(date = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())}`;
}

/** The day [n] days before [date]'s, as [dayOf] writes it. */
export function daysBefore(date, n) {
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate() - n);
  return dayOf(d);
}

/**
 * Add one request to [userId]'s counters for [day].
 *
 * @param {{sync?: boolean, rowsIn?: number, rowsOut?: number,
 *          bytesIn?: number, bytesOut?: number}} hit
 */
export function recordHit(db, userId, hit, day = dayOf()) {
  db.prepare(
    `INSERT INTO traffic (user_id, day, requests, syncs, rows_in, rows_out, bytes_in, bytes_out)
       VALUES (@user, @day, 1, @syncs, @rowsIn, @rowsOut, @bytesIn, @bytesOut)
     ON CONFLICT (user_id, day) DO UPDATE SET
       requests  = requests + 1,
       syncs     = syncs + excluded.syncs,
       rows_in   = rows_in + excluded.rows_in,
       rows_out  = rows_out + excluded.rows_out,
       bytes_in  = bytes_in + excluded.bytes_in,
       bytes_out = bytes_out + excluded.bytes_out`
  ).run({
    user: userId,
    day,
    syncs: hit.sync ? 1 : 0,
    rowsIn: hit.rowsIn ?? 0,
    rowsOut: hit.rowsOut ?? 0,
    bytesIn: hit.bytesIn ?? 0,
    bytesOut: hit.bytesOut ?? 0,
  });
}

/** Forget days older than [KEEP_DAYS] before [now]. */
export function pruneTraffic(db, now = new Date()) {
  return db.prepare('DELETE FROM traffic WHERE day < ?').run(daysBefore(now, KEEP_DAYS))
    .changes;
}

export function deleteTrafficFor(db, userId) {
  db.prepare('DELETE FROM traffic WHERE user_id = ?').run(userId);
}

/**
 * The Express middleware. Must be installed before the routes; see the header
 * for why it can still see the account a route's auth found.
 */
export function trafficRecorder(db) {
  let prunedOn = null;
  return (req, res, next) => {
    res.on('finish', () => {
      if (!req.userId) return;
      const counted = res.locals.traffic ?? {};
      try {
        const today = dayOf();
        if (prunedOn !== today) {
          prunedOn = today;
          pruneTraffic(db);
        }
        recordHit(
          db,
          req.userId,
          {
            sync: counted.sync === true,
            rowsIn: counted.rowsIn,
            rowsOut: counted.rowsOut,
            bytesIn: Number(req.get('content-length')) || 0,
            bytesOut: Number(res.get('content-length')) || 0,
          },
          today
        );
      } catch (err) {
        // Counting is a courtesy; a full disk or a locked database must never
        // turn into an error on a request that already succeeded.
        console.error('traffic: could not record a request:', err.message);
      }
    });
    next();
  };
}

const ZERO = {
  requests: 0,
  syncs: 0,
  rows_in: 0,
  rows_out: 0,
  bytes_in: 0,
  bytes_out: 0,
};

const SUMS = `SUM(requests) AS requests, SUM(syncs) AS syncs,
  SUM(rows_in) AS rows_in, SUM(rows_out) AS rows_out,
  SUM(bytes_in) AS bytes_in, SUM(bytes_out) AS bytes_out`;

/**
 * The overview the admin panel draws: every day of the last [days] (today
 * included, quiet days as zeros so a chart has no gaps to explain), and every
 * account with its totals over the same window.
 *
 * [extra] fills in what traffic.js does not own: per account, whatever the
 * caller knows (stored rows, blob bytes, devices online, last seen).
 */
export function trafficOverview(db, { days = 30, now = new Date(), users = [], extra = () => ({}) } = {}) {
  const from = daysBefore(now, days - 1);

  const byDay = new Map(
    db
      .prepare(
        `SELECT day, ${SUMS}, COUNT(*) AS active_users
           FROM traffic WHERE day >= ? GROUP BY day`
      )
      .all(from)
      .map((r) => [r.day, r])
  );
  const daily = [];
  for (let i = days - 1; i >= 0; i--) {
    const day = daysBefore(now, i);
    const r = byDay.get(day);
    daily.push({ day, ...ZERO, active_users: 0, ...(r ?? {}) });
  }

  const byUser = new Map(
    db
      .prepare(
        `SELECT user_id, ${SUMS}, COUNT(*) AS active_days, MAX(day) AS last_day
           FROM traffic WHERE day >= ? GROUP BY user_id`
      )
      .all(from)
      .map((r) => [r.user_id, r])
  );
  const accounts = users.map((u) => {
    const r = byUser.get(u.id) ?? {};
    return {
      id: u.id,
      label: u.label,
      admin: u.is_admin === 1,
      ...ZERO,
      active_days: 0,
      last_day: null,
      ...Object.fromEntries(Object.entries(r).filter(([k]) => k !== 'user_id')),
      ...extra(u),
    };
  });
  accounts.sort((a, b) => b.requests - a.requests || a.label.localeCompare(b.label));

  const totals = { ...ZERO };
  for (const d of daily) for (const k of Object.keys(ZERO)) totals[k] += d[k];

  return { from, to: dayOf(now), days, daily, users: accounts, totals };
}
