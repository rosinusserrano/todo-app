// Authentication.
//
// Currently LAN mode: one shared secret, one implicit user. But every stored
// row already carries a `user_id`, and every query is already scoped by it.
// That is the part that is painful to retrofit - adding a users table later is
// a contained change, whereas going back to scope a few dozen queries is where
// multi-user bugs get introduced. So the scoping exists from day one even
// though there is only ever one user in it today.
//
// To add real accounts later, `identify()` is the only function that changes:
// look the bearer token up in a tokens table and return the owning user id.

export const LAN_USER = 'local';

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
export function identify(req, { secret }) {
  const header = req.get('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) {
    throw new AuthError('Missing "Authorization: Bearer <token>" header');
  }

  const presented = match[1].trim();
  if (!timingSafeEqual(presented, secret)) {
    throw new AuthError('Invalid token');
  }
  return LAN_USER;
}

/**
 * Constant-time string compare, so a bad token cannot be recovered a character
 * at a time by timing the response. Overkill on a LAN; correct everywhere else,
 * and this is the code that will still be here when the server is exposed.
 */
function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
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
