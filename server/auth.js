// Authentication.
//
// Every stored row carries a `user_id` and every query is scoped by it, so the
// only question a request has to answer is *which* user it is. That is this
// file, and - as the single-user version of it predicted - `identify()` is the
// only function that had to change to get real accounts: it looks the bearer
// token up in the tokens table and returns the owning user id.
//
// The tokens table is the sole authority. There is deliberately no "and also
// accept the configured secret" branch here: a fallback that bypasses the table
// would mean a revoked token is not actually revoked. The bootstrap secret
// still works because it is *adopted into* the table at startup
// (`adoptBootstrapSecret`), not because it is checked separately.

import { isAdmin, resolveToken } from './users.js';

export { LAN_USER } from './users.js';

export class AuthError extends Error {
  constructor(message, status = 401) {
    super(message);
    this.status = status;
  }
}

/**
 * Resolve a request to a user id, or throw AuthError.
 * @returns {string} user id
 */
export function identify(req, { db }) {
  const header = req.get('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) {
    throw new AuthError('Missing "Authorization: Bearer <token>" header');
  }

  const found = resolveToken(db, match[1].trim());
  // One message for unknown, revoked and malformed alike: telling a caller that
  // a token was real but revoked tells them the token was real.
  if (!found) throw new AuthError('Invalid token');
  return found.userId;
}

export function middleware(config) {
  return (req, res, next) => {
    try {
      req.userId = identify(req, config);
      next();
    } catch (err) {
      if (err instanceof AuthError) {
        res.status(err.status).json({ error: err.message });
      } else {
        next(err);
      }
    }
  };
}

/**
 * Gate the admin routes. Runs *after* `middleware`, which is what set req.userId.
 *
 * Admin is a role on an ordinary account, not a separate credential: the same
 * bearer token that syncs is the one that administers, so this adds no second
 * thing to steal. 403 rather than 401 - the token is fine, the account simply
 * is not allowed - so a client can tell "log in again" from "not your server".
 */
export function adminOnly({ db }) {
  return (req, res, next) => {
    if (!isAdmin(db, req.userId)) {
      return res.status(403).json({ error: 'This account is not an admin of this server' });
    }
    next();
  };
}
