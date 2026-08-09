// Users and access tokens.
//
// One database, partitioned by `user_id` - not one file per user. Every row in
// db.js already carries a user_id and every query is already scoped by it (that
// scoping was written before there was anyone to scope), so the partition costs
// nothing here, while a file per user would need its own connection, its own
// `meta.seq` and its own migration run on open, all for the same isolation the
// WHERE clause already gives.
//
// Tokens are stored as a **SHA-256 of the token**, never the token itself. A
// token is therefore printed exactly once, when it is issued: if it is lost the
// answer is to issue another and revoke the old one, which is a two-second
// operation. The public `id` column exists so that revoking is possible at all -
// you cannot name a secret you do not store.
//
// The bootstrap secret (server/data/secret.txt, or TODO_SYNC_SECRET) is not a
// separate code path: it is adopted into this table on startup as the token of
// the `local` user, which is the user id every row written before multi-user
// already carries. So the owner's existing devices keep working, unchanged, and
// there is exactly one way to authenticate.

import { createHash, randomBytes } from 'node:crypto';

/// The implicit user of a single-user server, and the owner of every row
/// written before tokens existed. Not special-cased anywhere except adoption.
export const LAN_USER = 'local';

/// Label given to a token adopted from the bootstrap secret, so that rotating
/// the secret can find and retire the previous one.
const BOOTSTRAP_LABEL = 'bootstrap secret';

export function initUsers(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id         TEXT PRIMARY KEY,
      label      TEXT NOT NULL,
      is_admin   INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS tokens (
      id           TEXT PRIMARY KEY,
      hash         TEXT NOT NULL UNIQUE,
      user_id      TEXT NOT NULL,
      label        TEXT NOT NULL,
      created_at   TEXT NOT NULL,
      last_seen_at TEXT,
      revoked_at   TEXT
    );
  `);

  // Same reason db.js has addColumn: CREATE TABLE IF NOT EXISTS does nothing to
  // a table that already exists, so a server that ran the first multi-user
  // build has `users` without `is_admin` and would reject every query naming it.
  const column = (name) =>
    db.prepare(`SELECT 1 FROM pragma_table_info('users') WHERE name = ?`).get(name);

  if (!column('is_admin')) {
    db.exec(`ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0`);
  }
  // The single sign-on identity this account is, or null for a token-only
  // account. Nullable rather than a second table: an account has at most one
  // provider identity, and a join for one column would be a join for nothing.
  if (!column('oidc_sub')) {
    db.exec(`ALTER TABLE users ADD COLUMN oidc_sub TEXT`);
  }
  // Locally blocked. This exists *because* of SSO: a device token is revoked by
  // deleting it from the tokens table, but an SSO token is minted by Keycloak
  // and this server cannot un-issue one. Without a local block, "revoked is
  // revoked" - the property the tokens table was built around - would stop
  // holding the moment SSO was switched on.
  if (!column('blocked_at')) {
    db.exec(`ALTER TABLE users ADD COLUMN blocked_at TEXT`);
  }

  // Two accounts claiming one provider identity would make "who is this" a
  // question with two answers. Partial, so the token-only accounts (which all
  // have a null sub) do not collide with each other.
  db.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS users_oidc_sub
      ON users (oidc_sub) WHERE oidc_sub IS NOT NULL
  `);
}

function now() {
  return new Date().toISOString();
}

function hashToken(token) {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

/**
 * A readable-but-opaque user id: a slug of the label plus four random hex, so
 * the id is recognisable when reading rows by hand and still cannot be guessed
 * by anyone naming a user they want to write to.
 */
function newUserId(db, label) {
  const slug = label.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  for (;;) {
    const id = `${slug || 'user'}-${randomBytes(2).toString('hex')}`;
    const taken = db.prepare('SELECT 1 FROM users WHERE id = ?').get(id);
    if (!taken) return id;
  }
}

export function getUser(db, id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id) ?? null;
}

export function ensureUser(db, id, label, { admin = false } = {}) {
  db.prepare(
    'INSERT OR IGNORE INTO users (id, label, is_admin, created_at) VALUES (?, ?, ?, ?)'
  ).run(id, label, admin ? 1 : 0, now());
  return getUser(db, id);
}

/** Create a user with a generated id. Returns the row. */
export function createUser(db, label, { admin = false } = {}) {
  const id = newUserId(db, label);
  return ensureUser(db, id, label, { admin });
}

/** True when an operator has locked this account out locally. */
export function isBlocked(db, userId) {
  const user = getUser(db, userId);
  return !!user && !!user.blocked_at;
}

/**
 * Block or unblock an account.
 *
 * The only way to cut off an SSO identity from this end - see the blocked_at
 * comment in initUsers. Blocking does not delete anything, so unblocking
 * restores the account and its rows intact.
 */
export function setBlocked(db, userId, on) {
  if (!getUser(db, userId)) throw new Error(`no such user: ${userId}`);
  db.prepare('UPDATE users SET blocked_at = ? WHERE id = ?').run(on ? now() : null, userId);
  return getUser(db, userId);
}

/**
 * The account for a provider identity, created on first sight.
 *
 * Keyed on `sub`, never on email: an address changing hands in the directory
 * must not hand over the account with it. The label is refreshed on every
 * login so a rename in Keycloak shows up here, and the admin role is applied
 * the same way - the directory is the authority on both while SSO is on.
 *
 * Auto-provisioning is what makes "log in with the company account" work
 * without an invite step. If that is not wanted, the answer is to restrict who
 * can reach the client in Keycloak, which is where that policy belongs.
 */
export function userForOidc(db, sub, label, { admin = false } = {}) {
  const existing = db.prepare('SELECT * FROM users WHERE oidc_sub = ?').get(sub);
  if (existing) {
    db.prepare('UPDATE users SET label = ?, is_admin = ? WHERE id = ?')
      .run(label, admin ? 1 : 0, existing.id);
    return getUser(db, existing.id);
  }

  const id = newUserId(db, label);
  db.prepare(
    'INSERT INTO users (id, label, is_admin, oidc_sub, created_at) VALUES (?, ?, ?, ?, ?)'
  ).run(id, label, admin ? 1 : 0, sub, now());
  return getUser(db, id);
}

/**
 * Attach a provider identity to an account that already exists.
 *
 * The migration path onto SSO, and without it there is not one. A server that
 * has been running on the bootstrap secret has all its rows under `local`; the
 * first single-sign-on login would find no account for that `sub`, create a
 * fresh one, and present an empty todo list to somebody who has years of
 * tasks - correctly, and uselessly. Linking first means that login resolves to
 * the account the data is already in.
 *
 * Refuses rather than steals: a `sub` already attached elsewhere is somebody's
 * identity, and silently moving it would sign them into another person's
 * account.
 */
export function linkOidc(db, userId, sub) {
  const user = getUser(db, userId);
  if (!user) throw new Error(`no such user: ${userId}`);

  const holder = db.prepare('SELECT * FROM users WHERE oidc_sub = ?').get(sub);
  if (holder && holder.id !== userId) {
    throw new Error(
      `that identity is already linked to ${holder.label} (${holder.id}). ` +
        `Unlink or delete that account first.`,
    );
  }

  db.prepare('UPDATE users SET oidc_sub = ? WHERE id = ?').run(sub, userId);
  return getUser(db, userId);
}

/** Detach a provider identity, leaving the account and its rows alone. */
export function unlinkOidc(db, userId) {
  if (!getUser(db, userId)) throw new Error(`no such user: ${userId}`);
  db.prepare('UPDATE users SET oidc_sub = NULL WHERE id = ?').run(userId);
  return getUser(db, userId);
}

export function isAdmin(db, userId) {
  const user = getUser(db, userId);
  return !!user && user.is_admin === 1;
}

/**
 * Grant or drop admin.
 *
 * Refuses to remove the last admin: a server with no admin cannot be
 * administered from the app at all, and recovering means going back to the
 * machine and the CLI. Cheap guard against a one-click lockout.
 */
export function setAdmin(db, userId, on) {
  if (!getUser(db, userId)) throw new Error(`no such user: ${userId}`);
  if (!on) {
    const others = db
      .prepare('SELECT COUNT(*) AS n FROM users WHERE is_admin = 1 AND id != ?')
      .get(userId).n;
    if (others === 0) throw new Error('refusing to remove the only admin');
  }
  db.prepare('UPDATE users SET is_admin = ? WHERE id = ?').run(on ? 1 : 0, userId);
  return getUser(db, userId);
}

/** Forget a user's identity and every token they hold. Their rows go in db.js. */
export function deleteUserIdentity(db, userId) {
  db.prepare('DELETE FROM tokens WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM users WHERE id = ?').run(userId);
}

/**
 * Issue a token for a user.
 *
 * @returns {{token: string, id: string}} the plaintext token - this is the only
 *   time it exists anywhere, so the caller must show it to the human now.
 */
export function issueToken(db, userId, label = 'device') {
  if (!getUser(db, userId)) throw new Error(`no such user: ${userId}`);

  const token = randomBytes(24).toString('base64url');
  const id = randomBytes(4).toString('hex');
  db.prepare(
    `INSERT INTO tokens (id, hash, user_id, label, created_at) VALUES (?, ?, ?, ?, ?)`
  ).run(id, hashToken(token), userId, label, now());
  return { token, id };
}

/**
 * Resolve a presented token to its user, or null.
 *
 * The lookup is by hash on a UNIQUE index, so it neither scans every token nor
 * compares the secret byte by byte - there is no timing signal to recover a
 * token from, and it stays O(1) as users are added.
 */
export function resolveToken(db, presented) {
  if (typeof presented !== 'string' || !presented) return null;

  const row = db
    .prepare(`SELECT id, user_id, label, revoked_at FROM tokens WHERE hash = ?`)
    .get(hashToken(presented));
  if (!row || row.revoked_at) return null;

  // "Last seen" is for the operator listing, not for anything the protocol
  // depends on, so it is throttled: without this every /api/cursor poll from
  // every device would be a write.
  const stamp = now();
  const cutoff = new Date(Date.now() - 60_000).toISOString();
  db.prepare(
    `UPDATE tokens SET last_seen_at = ?
      WHERE id = ? AND (last_seen_at IS NULL OR last_seen_at < ?)`
  ).run(stamp, row.id, cutoff);

  return { userId: row.user_id, tokenId: row.id, tokenLabel: row.label };
}

export function revokeToken(db, tokenId) {
  const info = db
    .prepare('UPDATE tokens SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL')
    .run(now(), tokenId);
  return info.changes > 0;
}

export function listUsers(db) {
  return db
    .prepare(
      `SELECT u.id, u.label, u.is_admin, u.created_at,
              (SELECT COUNT(*) FROM tokens t
                WHERE t.user_id = u.id AND t.revoked_at IS NULL) AS active_tokens
         FROM users u ORDER BY u.created_at`
    )
    .all();
}

export function listTokens(db, userId = null) {
  const where = userId ? 'WHERE user_id = ?' : '';
  const args = userId ? [userId] : [];
  return db
    .prepare(
      `SELECT id, user_id, label, created_at, last_seen_at, revoked_at
         FROM tokens ${where} ORDER BY created_at`
    )
    .all(...args);
}

/**
 * Make the bootstrap secret a real token of the `local` user.
 *
 * Idempotent, and it *rotates*: if the operator changes TODO_SYNC_SECRET, the
 * previous bootstrap token is revoked rather than left as a second key that
 * still opens the door. Tokens issued to devices are untouched - only the one
 * this function itself created before.
 */
export function adoptBootstrapSecret(db, secret) {
  if (!secret) return null;

  // The bootstrap secret is printed on the server's own console, so holding it
  // means standing where the server runs - which is the definition of the
  // operator here. That is what makes this user the admin, and it is set on
  // every adopt rather than only at creation, so a server whose `local` user
  // predates admin (the first multi-user build) gains it on the next start
  // instead of having no admin at all.
  ensureUser(db, LAN_USER, 'local', { admin: true });
  db.prepare('UPDATE users SET is_admin = 1 WHERE id = ?').run(LAN_USER);

  const hash = hashToken(secret);
  const existing = db.prepare('SELECT id, revoked_at FROM tokens WHERE hash = ?').get(hash);

  if (!existing) {
    const id = randomBytes(4).toString('hex');
    db.prepare(
      `INSERT INTO tokens (id, hash, user_id, label, created_at) VALUES (?, ?, ?, ?, ?)`
    ).run(id, hash, LAN_USER, BOOTSTRAP_LABEL, now());
  } else if (existing.revoked_at) {
    // Restoring the secret to secret.txt/TODO_SYNC_SECRET is an explicit act by
    // whoever runs the server, and the file is theirs. Honour it.
    db.prepare('UPDATE tokens SET revoked_at = NULL WHERE id = ?').run(existing.id);
  }

  db.prepare(
    `UPDATE tokens SET revoked_at = ?
      WHERE label = ? AND hash != ? AND revoked_at IS NULL`
  ).run(now(), BOOTSTRAP_LABEL, hash);

  return LAN_USER;
}
