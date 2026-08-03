// Token administration.
//
//   npm run token -- add "Alice"                  new user + their first token
//   npm run token -- add --user alice-3f9c phone  another device for that user
//   npm run token -- list
//   npm run token -- revoke <token-id>
//
// A CLI rather than an HTTP endpoint on purpose: an admin endpoint would be a
// second authentication surface on a server whose whole security model is "one
// bearer token, on your LAN", and the operator is by definition sitting at the
// machine. It can be run while the server is up - SQLite is in WAL mode, so a
// second process writing is fine, and the server reads the tokens table per
// request rather than caching it, so a new token works immediately and a
// revoked one stops working immediately. No restart.
//
// Users are isolated by `user_id`, which is on every row and in every query:
// a second user gets an empty account on the same server, not a view of yours.

import { openDb } from './db.js';
import { DB_PATH } from './config.js';
import {
  createUser,
  getUser,
  issueToken,
  listTokens,
  listUsers,
  revokeToken,
  setAdmin,
} from './users.js';

const USAGE = `
Usage:
  npm run token -- add <label>                 create a user and print a token
  npm run token -- add --user <id> [label]     issue another token to a user
  npm run token -- list                        users, tokens and last use
  npm run token -- revoke <token-id>           stop a token working
  npm run token -- admin <user-id> [on|off]    grant or drop server admin

The token is shown once, when it is issued: only its hash is stored. If one is
lost, revoke it and issue another.

Admins can do all of the above from the app, under Settings. The account
holding the token the server prints is an admin already; this is here for the
case where that is not enough - or where nobody can log in at all.
`.trim();

function fail(message) {
  console.error(message);
  process.exit(1);
}

function printToken(db, userId, token, tokenId, label) {
  const user = getUser(db, userId);
  console.log('');
  console.log(`  user   ${user.label}  (${user.id})`);
  console.log(`  token  ${token}`);
  console.log(`  id     ${tokenId}   (${label} - use this to revoke)`);
  console.log('');
  console.log('  Enter the token in the app under Sync, with this server\'s address.');
  console.log('  It is not stored anywhere and will not be shown again.');
  console.log('');
}

function cmdAdd(db, args) {
  const userFlag = args.indexOf('--user');
  if (userFlag !== -1) {
    const userId = args[userFlag + 1];
    if (!userId) fail('--user needs a user id. See: npm run token -- list');
    if (!getUser(db, userId)) fail(`No such user: ${userId}`);

    const rest = args.filter((_, i) => i !== userFlag && i !== userFlag + 1);
    const label = rest.join(' ').trim() || 'device';
    const { token, id } = issueToken(db, userId, label);
    printToken(db, userId, token, id, label);
    return;
  }

  const label = args.join(' ').trim();
  if (!label) fail('A label is required: npm run token -- add "Alice"');

  const user = createUser(db, label);
  const { token, id } = issueToken(db, user.id, 'first device');
  printToken(db, user.id, token, id, 'first device');
}

function cmdList(db) {
  const users = listUsers(db);
  if (users.length === 0) {
    console.log('No users yet. Start the server once to adopt the bootstrap secret,');
    console.log('or run: npm run token -- add "<name>"');
    return;
  }

  for (const user of users) {
    console.log('');
    console.log(`${user.label}  (${user.id})${user.is_admin ? '  [admin]' : ''}`);
    for (const t of listTokens(db, user.id)) {
      const state = t.revoked_at
        ? 'revoked'
        : t.last_seen_at
          ? `last used ${t.last_seen_at.slice(0, 16).replace('T', ' ')}`
          : 'never used';
      console.log(`  ${t.id}  ${t.label.padEnd(20)} ${state}`);
    }
  }
  console.log('');
}

function cmdRevoke(db, args) {
  const id = args[0];
  if (!id) fail('Which token? See: npm run token -- list');
  if (!revokeToken(db, id)) fail(`No active token with id ${id}.`);
  console.log(`Revoked ${id}. That device will get "Invalid token" on its next sync.`);
}

function cmdAdmin(db, args) {
  const [userId, state = 'on'] = args;
  if (!userId) fail('Which user? See: npm run token -- list');
  if (!['on', 'off'].includes(state)) fail('Say "on" or "off".');

  try {
    const user = setAdmin(db, userId, state === 'on');
    console.log(
      user.is_admin
        ? `${user.label} (${user.id}) can now manage users from the app.`
        : `${user.label} (${user.id}) is no longer an admin.`
    );
  } catch (err) {
    fail(err.message);
  }
}

const [command, ...args] = process.argv.slice(2);
const db = openDb(DB_PATH);

switch (command) {
  case 'add':
    cmdAdd(db, args);
    break;
  case 'list':
    cmdList(db);
    break;
  case 'revoke':
    cmdRevoke(db, args);
    break;
  case 'admin':
    cmdAdmin(db, args);
    break;
  default:
    console.log(USAGE);
    process.exit(command ? 1 : 0);
}

db.close();
