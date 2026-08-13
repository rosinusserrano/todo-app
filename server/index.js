// Todo Widget sync server.
//
//   npm run server
//
// Self-contained: creates its own database and access token on first run, and
// prints the LAN address to type into a client. Configuration is by environment
// variable (see config.js), all optional.
//
// It serves more than one user: each access token belongs to a user, and every
// row is scoped to the user whose token pushed it, so a second person on the
// same server gets their own account rather than a second view of yours. Issue
// them a token with `npm run token -- add "<name>"`.

import express from 'express';
import { networkInterfaces } from 'node:os';

import { openDb, purgeUser, sync, userCursor, TABLES } from './db.js';
import { publish, subscribe } from './events.js';
import { adminOnly, middleware } from './auth.js';
import { DB_PATH, HOST, PORT, loadSecret } from './config.js';
import { OidcVerifier, oidcConfigFromEnv } from './oidc.js';
import {
  adoptBootstrapSecret,
  createUser,
  getUser,
  isAdmin,
  issueToken,
  listTokens,
  listUsers,
  revokeToken,
} from './users.js';

const SECRET = loadSecret();
const db = openDb(DB_PATH);

// The secret becomes the `local` user's token rather than a parallel way in -
// see users.js. This is what keeps every device set up before multi-user
// working, and pointing at the same rows: they already carry user_id 'local'.
adoptBootstrapSecret(db, SECRET);

// Single sign-on, when TODO_OIDC_ISSUER names a provider. Null otherwise, and
// null is what keeps identify() on the tokens table alone - the feature is off
// unless it was configured, rather than off unless it was disabled.
const OIDC_CONFIG = oidcConfigFromEnv();
const oidc = OIDC_CONFIG ? new OidcVerifier(OIDC_CONFIG) : null;

// Every route that authenticates shares one config object, so a route cannot be
// added that quietly authenticates against a different set of rules.
const auth = { db, oidc };

const app = express();
app.use(express.json({ limit: '8mb' }));

// ---------------------------------------------------------------- validation

// Rejecting malformed rows here keeps the merge in db.js simple, and means a
// buggy client cannot write a row that later crashes every *other* client on
// pull. Unknown fields are dropped rather than rejected, so an older server
// stays usable against a newer client.
function validateRow(table, row, index) {
  const where = `${table}[${index}]`;
  if (typeof row !== 'object' || row === null) {
    return `${where} is not an object`;
  }
  if (typeof row.uuid !== 'string' || !row.uuid || row.uuid.length > 64) {
    return `${where}.uuid must be a non-empty string of at most 64 chars`;
  }
  if (typeof row.updated_at !== 'string' || !row.updated_at) {
    return `${where}.updated_at must be a non-empty RFC 3339 string`;
  }
  if (row.deleted_at != null && typeof row.deleted_at !== 'string') {
    return `${where}.deleted_at must be a string or null`;
  }
  for (const field of TABLES[table]) {
    const v = row[field];
    if (v == null) continue;
    if (typeof v !== 'string' && typeof v !== 'number') {
      return `${where}.${field} must be a string, number or null`;
    }
  }
  return null;
}

function validatePayload(body) {
  if (typeof body !== 'object' || body === null) return 'body must be a JSON object';

  const since = body.since ?? 0;
  if (!Number.isInteger(since) || since < 0) return '"since" must be a non-negative integer';

  const changes = body.changes ?? {};
  if (typeof changes !== 'object' || changes === null) return '"changes" must be an object';

  for (const table of Object.keys(changes)) {
    if (!(table in TABLES)) return `unknown table "${table}"`;
    if (!Array.isArray(changes[table])) return `"changes.${table}" must be an array`;
    for (const [i, row] of changes[table].entries()) {
      const err = validateRow(table, row, i);
      if (err) return err;
    }
  }
  return null;
}

// -------------------------------------------------------------------- routes

// Unauthenticated: lets a client verify the address is reachable and is
// actually a todo-sync server before asking the user for a token.
app.get('/api/health', (_req, res) => {
  res.json({ ok: true, service: 'todo-widget-sync', version: 1 });
});

// Unauthenticated, and deliberately: a client has to know *whether* to offer
// "Sign in with SSO" before it has any credential to present. Everything here
// is already public - the issuer and client id are in every login URL, and the
// endpoints come from the provider's own published discovery document.
app.get('/api/auth/config', async (_req, res) => {
  if (!oidc) return res.json({ mode: 'token' });

  try {
    const doc = await oidc.discover();
    res.json({
      mode: 'oidc',
      issuer: oidc.config.issuer,
      client_id: oidc.config.clientId,
      device_authorization_endpoint: doc.device_authorization_endpoint ?? null,
      token_endpoint: doc.token_endpoint ?? null,
    });
  } catch (err) {
    // The server is up, SSO is configured, and the provider is not answering.
    // Saying so is more useful than falling back to 'token', which would have
    // the client quietly ask for a password-equivalent it should not need.
    res.status(503).json({ mode: 'oidc', error: String(err.message ?? err) });
  }
});

/// Which device is talking, for excluding it from the broadcast its own push
/// causes. Optional, untrusted and not a credential - the bearer token already
/// established *who* this is, and the worst a wrong value can do is cost its
/// owner one redundant sync. Length-capped so it cannot become a way to keep
/// arbitrary strings in server memory.
function deviceIdOf(req) {
  const raw = req.get('x-device-id');
  if (typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  return trimmed && trimmed.length <= 64 ? trimmed : null;
}

app.post('/api/sync', middleware(auth), (req, res, next) => {
  const problem = validatePayload(req.body);
  if (problem) return res.status(400).json({ error: problem });

  try {
    const { merged, ...result } = sync(
      db,
      req.userId,
      req.body.since ?? 0,
      req.body.changes ?? {}
    );
    res.json(result);

    // After responding, and only when rows actually landed. The push that
    // caused this is not waiting on the fan-out, and a hint is a courtesy: a
    // client that misses one still polls, so nothing here is worth failing a
    // sync over.
    if (merged > 0) {
      publish(req.userId, result.cursor, deviceIdOf(req));
    }
  } catch (err) {
    next(err);
  }
});

// The live half of sync: an open stream that says "your account moved", so the
// other devices do not have to wait for the next poll. See events.js - it
// carries no rows, only a nudge to run the sync that would have happened
// anyway, which is what keeps it from being a second way for data to arrive.
//
// Authenticated exactly like every other route. There is no query-parameter
// token: an URL travels through proxy logs and browser history in a way an
// Authorization header does not.
app.get('/api/events', middleware(auth), (req, res) => {
  subscribe(req.userId, deviceIdOf(req), res);
});

// Cheap way for a client to ask "is there anything new?" without uploading.
// Scoped to the caller: a global counter would move whenever *another* user
// wrote, and every client would sync on a poll with nothing to fetch.
app.get('/api/cursor', middleware(auth), (req, res) => {
  res.json({ cursor: userCursor(db, req.userId) });
});

// Which account a token belongs to. Lets a client show whose data it is holding
// - and lets whoever was handed a token check it works before typing a day of
// tasks into the wrong account. `admin` is what makes the app show the user
// management panel at all, so an ordinary account never sees a door it cannot
// open (the routes below still check for themselves - this only hides the UI).
app.get('/api/me', middleware(auth), (req, res) => {
  const user = getUser(db, req.userId);
  res.json({
    user: req.userId,
    label: user?.label ?? req.userId,
    admin: isAdmin(db, req.userId),
  });
});

// ------------------------------------------------------------------ admin api
//
// The same routes the CLI covers, for the app's user-management panel. They are
// not a second authentication surface: `adminOnly` is a role check on the token
// that is already syncing, so there is no extra credential to steal or leak. The
// CLI stays for the case the panel cannot help with - no admin token to hand.

const admin = [middleware(auth), adminOnly(auth)];

/// Labels end up in listings and in a user id; keep them sane rather than
/// letting a 4KB "name" through into every future console line.
function readLabel(value, fallback) {
  if (value == null) return fallback;
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return fallback;
  return trimmed.length <= 60 ? trimmed : null;
}

app.get('/api/admin/users', ...admin, (_req, res) => {
  res.json({
    users: listUsers(db).map((u) => ({
      id: u.id,
      label: u.label,
      admin: u.is_admin === 1,
      created_at: u.created_at,
      // Never the hash: it is not needed to administer anything, and shipping
      // it to a client turns a stolen response into an offline guessing target.
      tokens: listTokens(db, u.id).map((t) => ({
        id: t.id,
        label: t.label,
        created_at: t.created_at,
        last_seen_at: t.last_seen_at,
        revoked: t.revoked_at != null,
      })),
    })),
  });
});

// Creates the account *and* its first token, because an account nobody can log
// into is not a thing anyone wants to have made. The token is in the response
// once and never again.
app.post('/api/admin/users', ...admin, (req, res) => {
  const label = readLabel(req.body?.label, null);
  if (!label) return res.status(400).json({ error: 'A name is required (60 chars max)' });

  const user = createUser(db, label);
  const { token, id } = issueToken(db, user.id, 'first device');
  res.json({ user: { id: user.id, label: user.label, admin: false }, token, token_id: id });
});

app.post('/api/admin/users/:id/tokens', ...admin, (req, res) => {
  const user = getUser(db, req.params.id);
  if (!user) return res.status(404).json({ error: 'No such user' });

  const label = readLabel(req.body?.label, 'device');
  if (!label) return res.status(400).json({ error: 'Invalid token name (60 chars max)' });

  const { token, id } = issueToken(db, user.id, label);
  res.json({ token, token_id: id });
});

app.post('/api/admin/tokens/:id/revoke', ...admin, (req, res) => {
  const token = listTokens(db).find((t) => t.id === req.params.id);
  if (!token) return res.status(404).json({ error: 'No such token' });
  // Revoking your own last token locks you out of the server from this device,
  // and the panel you would use to fix it goes with it.
  if (token.user_id === req.userId) {
    const mine = listTokens(db, req.userId).filter((t) => !t.revoked_at);
    if (mine.length <= 1) {
      return res.status(400).json({ error: 'That is the token you are using right now' });
    }
  }
  if (!revokeToken(db, req.params.id)) {
    return res.status(400).json({ error: 'That token is already revoked' });
  }
  res.json({ ok: true });
});

// Deletes the account and everything in it. Their devices keep their local
// copies - this server simply stops knowing them.
app.delete('/api/admin/users/:id', ...admin, (req, res) => {
  const user = getUser(db, req.params.id);
  if (!user) return res.status(404).json({ error: 'No such user' });
  if (user.id === req.userId) {
    return res.status(400).json({ error: 'You cannot delete your own account' });
  }
  // An admin is someone who can undo this; make removing them a deliberate two
  // steps (drop admin, then delete) rather than one click on the wrong row.
  if (user.is_admin === 1) {
    return res.status(400).json({ error: 'Remove admin from this account first' });
  }

  const rows = purgeUser(db, user.id);
  res.json({ ok: true, rows });
});

app.use((err, _req, res, _next) => {
  console.error('[sync] unhandled:', err);
  res.status(500).json({ error: 'internal error' });
});

// --------------------------------------------------------------------- start

/// Addresses a client could plausibly reach this on, best guess first.
///
/// A machine with WSL, a VM or a VPN on it reports a handful of these, and only
/// one of them is the wifi the phone is also on - so the ordering matters more
/// than it looks. 169.254.x is dropped outright: that is what an interface
/// picks when DHCP failed, so it is never the answer.
function lanAddresses() {
  const rank = (ip) => {
    if (ip.startsWith('192.168.')) return 0; // home wifi, almost always
    if (ip.startsWith('10.')) return 1;
    if (/^172\.(1[6-9]|2\d|3[01])\./.test(ip)) return 2; // often a vSwitch
    return 3;
  };

  // Enumerating interfaces is a *sandboxed* syscall, not a safe one: it needs
  // AF_NETLINK, and the installed unit restricts address families to AF_INET
  // and AF_INET6 - so on a hardened deployment this throws EAFNOSUPPORT. The
  // unit now allows it, but this catch stays regardless, because the only thing
  // downstream of this list is a line of console output telling somebody which
  // address to type. A cosmetic banner must never be the reason the server does
  // not come up, and it was: the listen callback throwing crashed the process
  // *after* the port was already bound, so systemd restarted it into the same
  // crash forever.
  let interfaces;
  try {
    interfaces = networkInterfaces();
  } catch {
    return [];
  }

  return Object.values(interfaces)
    .flat()
    .filter((n) => n && n.family === 'IPv4' && !n.internal)
    .map((n) => n.address)
    .filter((ip) => !ip.startsWith('169.254.'))
    .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
}

app.listen(PORT, HOST, () => {
  const bar = '─'.repeat(58);
  console.log(`\n┌${bar}┐`);
  console.log('  Todo Widget sync server');
  console.log(`  db     ${DB_PATH}`);
  console.log(`  token  ${SECRET}`);
  console.log('');
  console.log('  Enter one of these in the app under Sync:');
  if (HOST === '127.0.0.1' || HOST === 'localhost') {
    console.log(`    http://127.0.0.1:${PORT}   (this machine only)`);
  } else {
    console.log(`    http://localhost:${PORT}`);
    const ips = lanAddresses();
    for (const ip of ips) {
      console.log(`    http://${ip}:${PORT}`);
    }
    if (ips.length > 1) {
      console.log('');
      console.log('  Several are listed because this machine has more than one');
      console.log('  network (a VM, WSL or a VPN adds its own). The right one is');
      console.log('  the one starting with the same numbers as your phone\'s IP.');
    }
  }

  const others = listUsers(db).filter((u) => u.id !== 'local');
  console.log('');
  if (others.length === 0) {
    console.log('  Someone else on this server? Give them their own account:');
    console.log('    npm run token -- add "<name>"');
  } else {
    console.log(`  Also serving ${others.length} other account(s):`);
    for (const u of others) {
      console.log(`    ${u.label}  (${u.id})  ${u.active_tokens} token(s)`);
    }
    console.log('  npm run token -- list');
  }
  console.log(`└${bar}┘\n`);
});
