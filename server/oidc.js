// Single sign-on against an OpenID Connect provider - Keycloak, in practice.
//
// The server does not run a login flow. Devices get an access token from the
// provider themselves (the device-authorization grant, see DEPLOY.md) and send
// it as the same `Authorization: Bearer` header a device token uses. All this
// file does is decide whether such a token is genuine, and whose it is.
//
// **No new dependencies.** node:crypto can build a public key straight from a
// JWK and verify an RS256 signature, so a JWT library would be a supply-chain
// risk taken for about thirty lines of code. What a library would also give is
// the mistakes-already-made list, so the checks below are deliberate and
// commented rather than terse:
//
//   - The algorithm is taken from an allow-list of *asymmetric* algorithms,
//     never from the token. `alg: none` is the obvious attack; `alg: HS256` is
//     the subtle one, where a token is signed with the provider's public key
//     as an HMAC secret and a naive verifier accepts it, because that key is
//     published.
//   - `iss` must equal the configured issuer exactly. Without it, any provider
//     anybody can sign up to is a valid issuer for this server.
//   - The audience must name our client, or the token is one issued for a
//     different application and merely happens to verify.
//   - `exp` is required. A token without one never expires.
//
// Identity is the `sub` claim, which is stable and opaque; the email is a label
// only. Mapping on email would mean an address changing hands in the directory
// silently hands over the account.

import { createPublicKey, verify as verifySignature } from 'node:crypto';

/** Seconds of tolerance for clock drift between here and the provider. */
const CLOCK_SKEW = 60;

/** How long a fetched JWKS is reused before being refetched. */
const JWKS_TTL_MS = 10 * 60 * 1000;

/** Floor on refetches triggered by an unknown `kid`, so a bad token cannot be
 *  turned into a request amplifier against the provider. */
const JWKS_MIN_REFETCH_MS = 30 * 1000;

const ALGS = {
  RS256: { alg: 'sha256' },
  RS384: { alg: 'sha384' },
  RS512: { alg: 'sha512' },
  PS256: { alg: 'sha256', pss: true },
  PS384: { alg: 'sha384', pss: true },
  PS512: { alg: 'sha512', pss: true },
  ES256: { alg: 'sha256', ec: true },
  ES384: { alg: 'sha384', ec: true },
  ES512: { alg: 'sha512', ec: true },
};

/** The credential is bad: forged, expired, for another app. The caller's fault. */
export class OidcError extends Error {}

/**
 * The provider could not be consulted - down, unreachable, or misconfigured.
 *
 * A separate type because the two must not produce the same HTTP status. If an
 * outage came back as "invalid token", every device would treat a Keycloak
 * restart as a signal to sign itself out, and a five-second blip would become
 * everybody logging in again.
 */
export class OidcUnavailable extends Error {}

function b64urlToBuffer(s) {
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function decodeJson(segment) {
  try {
    return JSON.parse(b64urlToBuffer(segment).toString('utf8'));
  } catch {
    throw new OidcError('Malformed token');
  }
}

/**
 * True when a string is shaped like a JWT.
 *
 * Used to route between the two credential kinds. It is a *shape* test, not a
 * trust decision - a device token is opaque and random, so it never has two
 * dots with base64url either side, and anything that does is meant to be
 * checked as a JWT and will fail properly if it is not one.
 */
export function looksLikeJwt(token) {
  const parts = token.split('.');
  return (
    parts.length === 3 && parts.every((p) => /^[A-Za-z0-9_-]+$/.test(p) && p.length > 0)
  );
}

/**
 * Reads the OIDC settings out of the environment.
 *
 * Returns null when `TODO_OIDC_ISSUER` is unset, which is what keeps this whole
 * feature off by default: a server nobody configured for SSO behaves exactly as
 * it did before, and `identify()` never reaches this file.
 */
export function oidcConfigFromEnv(env = process.env) {
  const issuer = (env.TODO_OIDC_ISSUER ?? '').trim().replace(/\/$/, '');
  if (!issuer) return null;

  return {
    issuer,
    clientId: (env.TODO_OIDC_CLIENT_ID ?? 'todo-widget').trim(),
    adminRole: (env.TODO_OIDC_ADMIN_ROLE ?? 'todo-admin').trim(),
    // Keycloak puts the client in `azp` and often only "account" in `aud`, so
    // by default we accept either. Set this to require a specific `aud`.
    audience: (env.TODO_OIDC_AUDIENCE ?? '').trim() || null,
  };
}

/**
 * A verifier bound to one provider.
 *
 * `fetchImpl` is injectable so the tests can serve a JWKS without a network or
 * a running Keycloak; nothing else should pass it.
 */
export class OidcVerifier {
  constructor(config, { fetchImpl = fetch } = {}) {
    this.config = config;
    this._fetch = fetchImpl;
    this._discovery = null;
    this._jwks = null;
    this._jwksAt = 0;
    this._lastRefetch = 0;
  }

  get discoveryUrl() {
    return `${this.config.issuer}/.well-known/openid-configuration`;
  }

  /** The provider's published endpoints, fetched once and kept. */
  async discover() {
    if (this._discovery) return this._discovery;

    let res;
    try {
      res = await this._fetch(this.discoveryUrl);
    } catch (err) {
      throw new OidcUnavailable(`Could not reach ${this.discoveryUrl}: ${err.message}`);
    }
    if (!res.ok) {
      throw new OidcUnavailable(`Could not read ${this.discoveryUrl}: HTTP ${res.status}`);
    }
    const doc = await res.json();
    if (doc.issuer !== this.config.issuer) {
      // The document is what tells us where the keys are, so a mismatch here
      // means we would be trusting keys the configured issuer never named.
      // Unavailable rather than invalid: it is a misconfiguration of this
      // server, and no token the caller could present would fix it.
      throw new OidcUnavailable(
        `Issuer mismatch: configured ${this.config.issuer}, document says ${doc.issuer}`,
      );
    }
    this._discovery = doc;
    return doc;
  }

  async _keys({ force = false } = {}) {
    const fresh = this._jwks && Date.now() - this._jwksAt < JWKS_TTL_MS;
    if (fresh && !force) return this._jwks;

    const { jwks_uri: uri } = await this.discover();
    if (!uri) throw new OidcUnavailable('Provider published no jwks_uri');

    let res;
    try {
      res = await this._fetch(uri);
    } catch (err) {
      throw new OidcUnavailable(`Could not reach the JWKS: ${err.message}`);
    }
    if (!res.ok) throw new OidcUnavailable(`Could not read JWKS: HTTP ${res.status}`);

    const doc = await res.json();
    this._jwks = Array.isArray(doc.keys) ? doc.keys : [];
    this._jwksAt = Date.now();
    return this._jwks;
  }

  /**
   * Find the signing key for a `kid`, refetching once if it is unknown.
   *
   * The refetch is what makes provider key rotation a non-event: a token signed
   * with a key minted five minutes ago is accepted without anybody restarting
   * this server. It is rate-limited because the trigger is attacker-controlled.
   */
  async _keyFor(kid) {
    let keys = await this._keys();
    let found = keys.find((k) => k.kid === kid);

    if (!found && Date.now() - this._lastRefetch > JWKS_MIN_REFETCH_MS) {
      this._lastRefetch = Date.now();
      keys = await this._keys({ force: true });
      found = keys.find((k) => k.kid === kid);
    }
    if (!found) throw new OidcError('Token signed with an unknown key');
    return found;
  }

  /**
   * Verify an access token and return its claims, or throw OidcError.
   */
  async verify(token, { now = Date.now() } = {}) {
    if (!looksLikeJwt(token)) throw new OidcError('Not a JWT');

    const [rawHeader, rawPayload, rawSig] = token.split('.');
    const header = decodeJson(rawHeader);
    const claims = decodeJson(rawPayload);

    // The allow-list, not the token, decides which algorithms exist here.
    const spec = ALGS[header.alg];
    if (!spec) throw new OidcError(`Unsupported algorithm: ${header.alg}`);

    const jwk = await this._keyFor(header.kid);
    let key;
    try {
      key = createPublicKey({ key: jwk, format: 'jwk' });
    } catch {
      throw new OidcUnavailable('Provider published a key this server cannot read');
    }

    const signed = Buffer.from(`${rawHeader}.${rawPayload}`, 'utf8');
    const sig = b64urlToBuffer(rawSig);
    const options = { key };
    if (spec.pss) options.padding = 1 << 5; // RSA_PKCS1_PSS_PADDING
    if (spec.ec) options.dsaEncoding = 'ieee-p1363'; // JOSE uses raw r||s

    if (!verifySignature(spec.alg, signed, options, sig)) {
      throw new OidcError('Bad signature');
    }

    this._checkClaims(claims, now);
    return claims;
  }

  _checkClaims(claims, now) {
    const seconds = Math.floor(now / 1000);

    if (claims.iss !== this.config.issuer) {
      throw new OidcError('Token was issued by a different provider');
    }
    if (typeof claims.exp !== 'number') {
      throw new OidcError('Token has no expiry');
    }
    if (seconds > claims.exp + CLOCK_SKEW) {
      throw new OidcError('Token has expired');
    }
    if (typeof claims.nbf === 'number' && seconds + CLOCK_SKEW < claims.nbf) {
      throw new OidcError('Token is not valid yet');
    }

    const wanted = this.config.audience ?? this.config.clientId;
    const aud = claims.aud == null ? [] : [].concat(claims.aud);
    // `azp` counts because Keycloak names the client there and leaves `aud` as
    // "account" unless an audience mapper has been added - requiring `aud`
    // alone would reject the default, correct configuration.
    const ok = aud.includes(wanted) || claims.azp === wanted;
    if (!ok) throw new OidcError('Token was issued for a different application');
  }
}

/**
 * A display name for the account, best-effort and never used for identity.
 */
export function labelFor(claims) {
  return (
    claims.preferred_username ||
    claims.email ||
    claims.name ||
    `sso-${String(claims.sub).slice(0, 8)}`
  );
}

/** True when the token carries the realm role that grants admin. */
export function claimsAreAdmin(claims, adminRole) {
  const realm = claims.realm_access?.roles;
  return Array.isArray(realm) && realm.includes(adminRole);
}
