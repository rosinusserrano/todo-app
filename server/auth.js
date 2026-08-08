// Authentication.
//
// Every stored row carries a `user_id` and every query is scoped by it, so the
// only question a request has to answer is *which* user it is. That is this
// file, and - as the single-user version of it predicted - `identify()` is the
// only function that had to change to get real accounts: it looks the bearer
// token up in the tokens table and returns the owning user id.
//
// There are exactly **two** kinds of credential, and no third:
//
//   1. A device token, opaque and random, stored in the tokens table as a
//      SHA-256. There is deliberately no "and also accept the configured
//      secret" branch: a fallback that bypassed the table would mean a revoked
//      token is not actually revoked. The bootstrap secret still works because
//      it is *adopted into* the table at startup (`adoptBootstrapSecret`), not
//      because it is checked separately.
//
//   2. An OIDC access token from the configured provider (Keycloak), which
//      exists only when TODO_OIDC_ISSUER is set. This is a second authority,
//      and it is worth being honest that it is one - but it does not reopen the
//      hole that the no-fallback rule closed, because it is not a bypass of the
//      table, it is a different table: the provider's. Two properties keep the
//      "revoked is revoked" guarantee intact:
//
//        - Access tokens are short-lived (minutes). Disabling an account in
//          Keycloak stops the refresh, so access stops on its own.
//        - `blocked_at` on the local user is checked on every request, so an
//          operator here can cut an SSO identity off immediately without
//          waiting for, or having access to, the directory.
//
// Which kind a credential is, is decided by its *shape* (`looksLikeJwt`), not
// by trying one and falling through to the other. Falling through would make a
// failed JWT quietly become a tokens-table lookup, and the error a caller gets
// back would stop describing what was actually wrong with their credential.

import { isBlocked, isAdmin, resolveToken, userForOidc } from './users.js';
import { claimsAreAdmin, labelFor, looksLikeJwt, OidcError } from './oidc.js';

export { LAN_USER } from './users.js';

export class AuthError extends Error {
  constructor(message, status = 401) {
    super(message);
    this.status = status;
  }
}

function bearer(req) {
  const header = req.get('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) {
    throw new AuthError('Missing "Authorization: Bearer <token>" header');
  }
  return match[1].trim();
}

/**
 * Resolve a request to a user id, or throw AuthError.
 *
 * Async because verifying an OIDC token may need the provider's keys. The
 * token-only path still resolves without awaiting anything real.
 *
 * @returns {Promise<string>} user id
 */
export async function identify(req, { db, oidc = null }) {
  const presented = bearer(req);

  const userId = oidc && looksLikeJwt(presented)
    ? await identifyOidc(presented, { db, oidc })
    : identifyToken(presented, { db });

  // Checked for both kinds, and last, so that blocking an account is one
  // switch rather than one per credential type.
  if (isBlocked(db, userId)) {
    throw new AuthError('This account has been blocked on this server', 403);
  }
  return userId;
}

function identifyToken(presented, { db }) {
  const found = resolveToken(db, presented);
  // One message for unknown, revoked and malformed alike: telling a caller that
  // a token was real but revoked tells them the token was real.
  if (!found) throw new AuthError('Invalid token');
  return found.userId;
}

async function identifyOidc(presented, { db, oidc }) {
  let claims;
  try {
    claims = await oidc.verify(presented);
  } catch (err) {
    if (err instanceof OidcError) {
      // Safe to be specific here in a way the token path is not: the token was
      // issued by a provider the caller can already talk to, so "expired" tells
      // them nothing they cannot find out by decoding their own token.
      throw new AuthError(`Single sign-on rejected: ${err.message}`);
    }
    // A provider that is down must not read as a bad credential, or every
    // device will helpfully log itself out.
    throw new AuthError('Could not reach the single sign-on provider', 503);
  }

  if (!claims.sub) throw new AuthError('Single sign-on token carries no subject');

  const user = userForOidc(db, claims.sub, labelFor(claims), {
    admin: claimsAreAdmin(claims, oidc.config.adminRole),
  });
  return user.id;
}

export function middleware(config) {
  return (req, res, next) => {
    identify(req, config)
      .then((userId) => {
        req.userId = userId;
        next();
      })
      .catch((err) => {
        if (err instanceof AuthError) {
          res.status(err.status).json({ error: err.message });
        } else {
          next(err);
        }
      });
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
