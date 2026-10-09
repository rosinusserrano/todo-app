// Where the server keeps things, shared by the server and the token CLI.
//
// It lives in its own file so that `tokens.js` cannot drift from `index.js`
// about which database it is talking to - a CLI that mints tokens into a
// different file than the one the server reads fails in the most confusing way
// available ("I made a token and it says invalid").
//
// All optional:
//   TODO_SYNC_PORT    default 8787
//   TODO_SYNC_DB      default ./server/data/sync.db
//   TODO_SYNC_SECRET  default: generated once into secret.txt beside the database
//   TODO_SYNC_HOST    default 0.0.0.0 (set to 127.0.0.1 to refuse LAN clients)
//   TODO_SYNC_WEB     default ./app/build/web; the Flutter web build to serve

import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const PORT = Number(process.env.TODO_SYNC_PORT ?? 8787);
export const HOST = process.env.TODO_SYNC_HOST ?? '0.0.0.0';
export const DB_PATH = resolve(process.env.TODO_SYNC_DB ?? 'server/data/sync.db');
// Beside the database, never at a path of its own. The two are one piece of
// state - the installed service is given exactly one writable directory
// (`ReadWritePaths=/var/lib/todo-sync`, everything else read-only under
// `ProtectSystem=strict`), so a secret resolved relative to the *working*
// directory lands in the read-only install tree and the server cannot start at
// all. Deriving it from `TODO_SYNC_DB` is also the only way one setting can
// move the state: pointing the database at a scratch file used to leave the
// secret behind in the previous one.
export const SECRET_PATH = resolve(dirname(DB_PATH), 'secret.txt');

/**
 * The bootstrap secret: the owner's token, from before there were tokens.
 *
 * Generates one on first run. Only the server calls this - the CLI must not
 * create a secret as a side effect of listing users.
 */
export function loadSecret() {
  if (process.env.TODO_SYNC_SECRET) return process.env.TODO_SYNC_SECRET;
  if (existsSync(SECRET_PATH)) return readFileSync(SECRET_PATH, 'utf8').trim();

  const secret = randomBytes(24).toString('base64url');
  mkdirSync(dirname(SECRET_PATH), { recursive: true });
  writeFileSync(SECRET_PATH, secret + '\n', { mode: 0o600 });
  return secret;
}

/**
 * The built Flutter web client, served by this same server so the browser talks
 * to `/api/*` on the origin it was loaded from - no CORS, no allow-list to keep
 * in step with a hostname, and no second thing to deploy. Same arrangement as
 * `../link-gateway-app`.
 *
 * Defaults to the build output in this repository, so `flutter build web`
 * followed by `npm run server` serves the site without configuration. The
 * installed service sets `TODO_SYNC_WEB` to wherever the copy lives.
 *
 * Serving is skipped entirely when the directory has no index.html, because a
 * sync server with no web build is the ordinary case.
 */
export const WEB_ROOT = resolve(
  process.env.TODO_SYNC_WEB ??
    fileURLToPath(new URL('../app/build/web', import.meta.url))
);
