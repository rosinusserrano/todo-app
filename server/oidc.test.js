// Single sign-on tests.
//
// No Keycloak and no network: the test generates its own RSA keypair, serves
// the public half as a JWKS through an injected fetch, and signs its own
// tokens. That is the whole point of taking `fetchImpl` - the verifier's rules
// are testable without standing up a provider, and the rules are the part that
// has to be right.

import test from 'node:test';
import assert from 'node:assert/strict';
import { createSign, generateKeyPairSync, randomUUID } from 'node:crypto';
import Database from 'better-sqlite3';

import { OidcVerifier, OidcError, looksLikeJwt, oidcConfigFromEnv, claimsAreAdmin } from './oidc.js';
import { identify, AuthError } from './auth.js';
import {
  ensureUser,
  initUsers,
  isAdmin,
  linkOidc,
  setBlocked,
  unlinkOidc,
  userForOidc,
} from './users.js';
import { openDb, sync } from './db.js';

const ISSUER = 'https://kc.example.test/realms/home';
const CLIENT = 'todo-widget';

const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const KID = 'test-key-1';

/** The public half as a JWKS entry, which is exactly what Keycloak publishes. */
function jwks(kid = KID) {
  const jwk = publicKey.export({ format: 'jwk' });
  return { keys: [{ ...jwk, kid, alg: 'RS256', use: 'sig' }] };
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

/** Sign a token the way the provider would. */
function makeToken(claims = {}, { kid = KID, alg = 'RS256', key = privateKey } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg, typ: 'JWT', kid }));
  const payload = b64url(
    JSON.stringify({
      iss: ISSUER,
      sub: randomUUID(),
      azp: CLIENT,
      aud: 'account',
      exp: now + 300,
      iat: now,
      preferred_username: 'marco',
      email: 'marco@example.test',
      ...claims,
    }),
  );
  const signed = `${header}.${payload}`;
  if (alg === 'none') return `${signed}.`;

  const sig = createSign('sha256').update(signed).sign(key);
  return `${signed}.${b64url(sig)}`;
}

/** A fetch that serves discovery + JWKS, and counts the calls. */
function stubFetch({ keys = jwks(), discovery = {} } = {}) {
  const calls = { discovery: 0, jwks: 0 };
  const doc = {
    issuer: ISSUER,
    jwks_uri: `${ISSUER}/protocol/openid-connect/certs`,
    token_endpoint: `${ISSUER}/protocol/openid-connect/token`,
    device_authorization_endpoint: `${ISSUER}/protocol/openid-connect/auth/device`,
    ...discovery,
  };

  const impl = async (url) => {
    if (String(url).endsWith('/.well-known/openid-configuration')) {
      calls.discovery++;
      return { ok: true, status: 200, json: async () => doc };
    }
    if (String(url) === doc.jwks_uri) {
      calls.jwks++;
      return { ok: true, status: 200, json: async () => (typeof keys === 'function' ? keys() : keys) };
    }
    return { ok: false, status: 404, json: async () => ({}) };
  };
  impl.calls = calls;
  return impl;
}

function verifier(opts = {}) {
  return new OidcVerifier(
    { issuer: ISSUER, clientId: CLIENT, adminRole: 'todo-admin', audience: null },
    { fetchImpl: stubFetch(opts) },
  );
}

test('a genuine token verifies and yields its claims', async () => {
  const v = verifier();
  const claims = await v.verify(makeToken({ sub: 'abc-123' }));
  assert.equal(claims.sub, 'abc-123');
  assert.equal(claims.preferred_username, 'marco');
});

test('a token signed by somebody else is rejected', async () => {
  // The attack this is really about: anyone can generate a keypair and mint a
  // well-formed token. Only the signature separates it from a real one.
  const other = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const v = verifier();
  await assert.rejects(
    () => v.verify(makeToken({}, { key: other.privateKey })),
    OidcError,
  );
});

test('alg: none is refused', async () => {
  const v = verifier();
  await assert.rejects(() => v.verify(makeToken({}, { alg: 'none' })), OidcError);
});

test('a symmetric alg is refused even though the key is public', async () => {
  // The subtle one: HS256 "signed" with the provider's published public key as
  // the HMAC secret. A verifier that took the algorithm from the token would
  // accept it, because that key is not a secret at all.
  const jwk = publicKey.export({ format: 'jwk' });
  const secret = Buffer.from(JSON.stringify(jwk));
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT', kid: KID }));
  const payload = b64url(JSON.stringify({ iss: ISSUER, sub: 'x', azp: CLIENT, exp: now + 300 }));
  const { createHmac } = await import('node:crypto');
  const sig = b64url(createHmac('sha256', secret).update(`${header}.${payload}`).digest());

  const v = verifier();
  await assert.rejects(() => v.verify(`${header}.${payload}.${sig}`), OidcError);
});

test('a token from another issuer is rejected', async () => {
  const v = verifier();
  await assert.rejects(
    () => v.verify(makeToken({ iss: 'https://evil.example.test/realms/home' })),
    OidcError,
  );
});

test('an expired token is rejected, and a not-yet-valid one too', async () => {
  const now = Math.floor(Date.now() / 1000);
  const v = verifier();

  await assert.rejects(() => v.verify(makeToken({ exp: now - 3600 })), OidcError);
  await assert.rejects(() => v.verify(makeToken({ nbf: now + 3600 })), OidcError);
});

test('a token with no expiry is rejected', async () => {
  const v = verifier();
  const token = makeToken({});
  // Rebuild without exp rather than setting it to undefined, which JSON drops.
  const [h, p, s] = token.split('.');
  const claims = JSON.parse(Buffer.from(p, 'base64url').toString());
  delete claims.exp;
  const repacked = `${h}.${b64url(JSON.stringify(claims))}.${s}`;

  // The signature no longer matches either, so assert on the specific failure
  // by signing the repacked body properly.
  const signed = `${h}.${b64url(JSON.stringify(claims))}`;
  const sig = b64url(createSign('sha256').update(signed).sign(privateKey));
  await assert.rejects(() => v.verify(`${signed}.${sig}`), /no expiry/);
  assert.ok(repacked);
});

test('a token for a different application is rejected', async () => {
  const v = verifier();
  await assert.rejects(
    () => v.verify(makeToken({ azp: 'some-other-app', aud: 'some-other-app' })),
    /different application/,
  );
});

test('aud naming our client is enough, as is azp', async () => {
  const v = verifier();
  // Keycloak's default shape: aud is "account", azp is the client.
  assert.ok(await v.verify(makeToken({ aud: 'account', azp: CLIENT })));
  // And with an audience mapper configured, aud names the client directly.
  assert.ok(await v.verify(makeToken({ aud: [CLIENT, 'account'], azp: 'other' })));
});

test('an unknown kid triggers exactly one refetch, then fails', async () => {
  // Key rotation must not need a restart, but an attacker-chosen kid must not
  // be a way to hammer the provider either.
  const fetchImpl = stubFetch();
  const v = new OidcVerifier(
    { issuer: ISSUER, clientId: CLIENT, adminRole: 'todo-admin', audience: null },
    { fetchImpl },
  );

  await v.verify(makeToken());
  const jwksCalls = fetchImpl.calls.jwks;

  await assert.rejects(() => v.verify(makeToken({}, { kid: 'nope' })), /unknown key/);
  assert.equal(fetchImpl.calls.jwks, jwksCalls + 1, 'one refetch');

  await assert.rejects(() => v.verify(makeToken({}, { kid: 'nope' })), /unknown key/);
  assert.equal(fetchImpl.calls.jwks, jwksCalls + 1, 'and no more, within the window');
});

test('a discovery document naming a different issuer is refused', async () => {
  // The document is what tells us where the keys live, so trusting one that
  // disagrees would mean trusting keys the configured issuer never named.
  const v = new OidcVerifier(
    { issuer: ISSUER, clientId: CLIENT, adminRole: 'todo-admin', audience: null },
    { fetchImpl: stubFetch({ discovery: { issuer: 'https://elsewhere.test' } }) },
  );
  await assert.rejects(() => v.discover(), /Issuer mismatch/);
});

test('looksLikeJwt separates the two credential kinds', () => {
  assert.ok(looksLikeJwt(makeToken()));
  // What `npm run token -- add` produces: base64url, no dots.
  assert.equal(looksLikeJwt('Zm9vYmFyYmF6cXV1eA'), false);
  assert.equal(looksLikeJwt('a.b'), false);
  assert.equal(looksLikeJwt('a..c'), false);
});

test('the feature is off unless an issuer is configured', () => {
  assert.equal(oidcConfigFromEnv({}), null);
  assert.equal(oidcConfigFromEnv({ TODO_OIDC_ISSUER: '   ' }), null);

  const cfg = oidcConfigFromEnv({ TODO_OIDC_ISSUER: `${ISSUER}/` });
  assert.equal(cfg.issuer, ISSUER, 'trailing slash trimmed to match the iss claim');
  assert.equal(cfg.clientId, 'todo-widget');
  assert.equal(cfg.adminRole, 'todo-admin');
});

test('admin comes from a realm role', () => {
  assert.ok(claimsAreAdmin({ realm_access: { roles: ['todo-admin', 'x'] } }, 'todo-admin'));
  assert.equal(claimsAreAdmin({ realm_access: { roles: ['x'] } }, 'todo-admin'), false);
  assert.equal(claimsAreAdmin({}, 'todo-admin'), false);
});

// ------------------------------------------------------------------ identify

function freshDb() {
  const db = new Database(':memory:');
  initUsers(db);
  return db;
}

/// A database with the sync tables as well, for the tests that push rows
/// through rather than only exercising the identity mapping.
function freshSyncDb() {
  return openDb(':memory:');
}

function req(authorization) {
  return { get: (name) => (name.toLowerCase() === 'authorization' ? authorization : undefined) };
}

test('an SSO token provisions an account on first sight and reuses it after', async () => {
  const db = freshDb();
  const oidc = verifier();
  const sub = 'kc-sub-1';

  const first = await identify(req(`Bearer ${makeToken({ sub })}`), { db, oidc });
  const again = await identify(req(`Bearer ${makeToken({ sub })}`), { db, oidc });

  assert.equal(first, again, 'the same person is the same account');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, 1);
});

test('identity is the subject, not the email', async () => {
  // An address changing hands in the directory must not hand over the account.
  const db = freshDb();
  const oidc = verifier();

  const a = await identify(req(`Bearer ${makeToken({ sub: 's-1', email: 'a@x.test' })}`), { db, oidc });
  const b = await identify(req(`Bearer ${makeToken({ sub: 's-2', email: 'a@x.test' })}`), { db, oidc });
  assert.notEqual(a, b);
});

test('the realm role grants admin, and losing it takes admin away', async () => {
  const db = freshDb();
  const oidc = verifier();
  const sub = 'kc-sub-admin';

  const id = await identify(
    req(`Bearer ${makeToken({ sub, realm_access: { roles: ['todo-admin'] } })}`),
    { db, oidc },
  );
  assert.ok(isAdmin(db, id));

  // The directory is the authority while SSO is on, so a role removed there
  // has to be a role removed here on the next request.
  await identify(req(`Bearer ${makeToken({ sub, realm_access: { roles: [] } })}`), { db, oidc });
  assert.equal(isAdmin(db, id), false);
});

test('a blocked account is refused even with a valid SSO token', async () => {
  // This is the property that keeps "revoked is revoked" true once SSO is on:
  // the server cannot un-issue a Keycloak token, so it must be able to refuse
  // one.
  const db = freshDb();
  const oidc = verifier();
  const sub = 'kc-sub-blocked';

  const id = await identify(req(`Bearer ${makeToken({ sub })}`), { db, oidc });
  setBlocked(db, id, true);

  await assert.rejects(
    () => identify(req(`Bearer ${makeToken({ sub })}`), { db, oidc }),
    (err) => err instanceof AuthError && err.status === 403,
  );

  setBlocked(db, id, false);
  assert.equal(await identify(req(`Bearer ${makeToken({ sub })}`), { db, oidc }), id);
});

test('a provider that is down is a 503, not a bad credential', async () => {
  // Otherwise every device logs itself out the moment Keycloak restarts.
  const db = freshDb();
  const down = new OidcVerifier(
    { issuer: ISSUER, clientId: CLIENT, adminRole: 'todo-admin', audience: null },
    { fetchImpl: async () => ({ ok: false, status: 502, json: async () => ({}) }) },
  );

  await assert.rejects(
    () => identify(req(`Bearer ${makeToken()}`), { db, oidc: down }),
    (err) => err instanceof AuthError && err.status === 503,
  );
});

test('with SSO off, a JWT is just an invalid device token', async () => {
  const db = freshDb();
  await assert.rejects(
    () => identify(req(`Bearer ${makeToken()}`), { db, oidc: null }),
    (err) => err instanceof AuthError && err.status === 401,
  );
});

test('device tokens still work alongside SSO', async () => {
  // The CLI path has to keep working: it is what fixes a server nobody can log
  // in to.
  const db = freshDb();
  const oidc = verifier();
  const { createUser, issueToken } = await import('./users.js');
  const user = createUser(db, 'CLI user');
  const { token } = issueToken(db, user.id, 'laptop');

  assert.equal(await identify(req(`Bearer ${token}`), { db, oidc }), user.id);
});

test('two devices signing in as one person share one account', async () => {
  // The thing that has to work: Windows and iOS, same Keycloak user, same
  // tasks. Each device runs its own device-grant sign-in and holds its own
  // tokens, so these are genuinely two independent credentials - the account
  // is the same only because `sub` is.
  const db = freshDb();
  const oidc = verifier();
  const sub = 'kc-one-person';

  const windows = await identify(
    req(`Bearer ${makeToken({ sub, azp: CLIENT })}`),
    { db, oidc },
  );
  const iphone = await identify(
    req(`Bearer ${makeToken({ sub, azp: CLIENT })}`),
    { db, oidc },
  );

  assert.equal(windows, iphone);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, 1);
});

test('a task pushed from one device comes back on the other', async () => {
  // End to end through the actual sync, not just the id mapping: the partition
  // is by user_id, so proving both devices resolve to one id is only half of it.
  const db = freshSyncDb();
  const oidc = verifier();
  const sub = 'kc-sync-across';

  const fromWindows = await identify(req(`Bearer ${makeToken({ sub })}`), { db, oidc });
  sync(db, fromWindows, 0, {
    tasks: [
      {
        uuid: 't-1',
        workspace_uuid: 'ws-1',
        text: 'written on the desktop',
        created_at: '2026-08-09T09:00:00Z',
        completed_at: null,
        sort_order: 0,
        in_progress: 0,
        updated_at: '2026-08-09T09:00:00Z',
        deleted_at: null,
      },
    ],
  });

  const fromPhone = await identify(req(`Bearer ${makeToken({ sub })}`), { db, oidc });
  const { changes } = sync(db, fromPhone, 0, {});
  assert.equal(changes.tasks.length, 1);
  assert.equal(changes.tasks[0].text, 'written on the desktop');
});

test('linking moves an existing account onto SSO instead of stranding it', async () => {
  // The migration that matters for a server that has been running on the
  // bootstrap secret: without the link, the first SSO login is a brand new,
  // empty account and years of tasks are still sitting under `local`.
  const db = freshSyncDb();
  const oidc = verifier();
  const sub = 'kc-the-owner';

  ensureUser(db, 'local', 'The owner');
  sync(db, 'local', 0, {
    tasks: [
      {
        uuid: 't-old',
        workspace_uuid: 'ws-1',
        text: 'from before SSO',
        created_at: '2026-01-01T09:00:00Z',
        completed_at: null,
        sort_order: 0,
        in_progress: 0,
        updated_at: '2026-01-01T09:00:00Z',
        deleted_at: null,
      },
    ],
  });

  linkOidc(db, 'local', sub);

  const who = await identify(req(`Bearer ${makeToken({ sub })}`), { db, oidc });
  assert.equal(who, 'local', 'signing in lands on the account with the data');

  const { changes } = sync(db, who, 0, {});
  assert.equal(changes.tasks[0].text, 'from before SSO');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, 1);
});

test('linking refuses to steal an identity from another account', () => {
  const db = freshDb();
  ensureUser(db, 'alice', 'Alice');
  ensureUser(db, 'bob', 'Bob');
  linkOidc(db, 'alice', 'sub-shared');

  assert.throws(() => linkOidc(db, 'bob', 'sub-shared'), /already linked/);
  // Unlinking frees it, which is the documented way out of a stray account.
  unlinkOidc(db, 'alice');
  assert.equal(linkOidc(db, 'bob', 'sub-shared').id, 'bob');
});

test('userForOidc refuses to let two accounts claim one identity', () => {
  const db = freshDb();
  const a = userForOidc(db, 'sub-x', 'marco');
  const b = userForOidc(db, 'sub-x', 'marco renamed');
  assert.equal(a.id, b.id);
  assert.equal(b.label, 'marco renamed', 'the label follows the directory');
});
