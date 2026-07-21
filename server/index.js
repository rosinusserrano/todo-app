// Todo Widget sync server.
//
//   npm run server
//
// Self-contained: creates its own database and access token on first run, and
// prints the LAN address to type into a client. Configuration is by environment
// variable, all optional:
//
//   TODO_SYNC_PORT    default 8787
//   TODO_SYNC_DB      default ./server/data/sync.db
//   TODO_SYNC_SECRET  default: generated once into ./server/data/secret.txt
//   TODO_SYNC_HOST    default 0.0.0.0 (set to 127.0.0.1 to refuse LAN clients)

import express from 'express';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { networkInterfaces } from 'node:os';
import { dirname, resolve } from 'node:path';

import { openDb, sync, currentSeq, TABLES } from './db.js';
import { middleware } from './auth.js';

const PORT = Number(process.env.TODO_SYNC_PORT ?? 8787);
const HOST = process.env.TODO_SYNC_HOST ?? '0.0.0.0';
const DB_PATH = resolve(process.env.TODO_SYNC_DB ?? 'server/data/sync.db');
const SECRET_PATH = resolve('server/data/secret.txt');

function loadSecret() {
  if (process.env.TODO_SYNC_SECRET) return process.env.TODO_SYNC_SECRET;
  if (existsSync(SECRET_PATH)) return readFileSync(SECRET_PATH, 'utf8').trim();

  const secret = randomBytes(24).toString('base64url');
  mkdirSync(dirname(SECRET_PATH), { recursive: true });
  writeFileSync(SECRET_PATH, secret + '\n', { mode: 0o600 });
  return secret;
}

const SECRET = loadSecret();
const db = openDb(DB_PATH);
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

app.post('/api/sync', middleware({ secret: SECRET }), (req, res, next) => {
  const problem = validatePayload(req.body);
  if (problem) return res.status(400).json({ error: problem });

  try {
    const result = sync(db, req.userId, req.body.since ?? 0, req.body.changes ?? {});
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// Cheap way for a client to ask "is there anything new?" without uploading.
app.get('/api/cursor', middleware({ secret: SECRET }), (_req, res) => {
  res.json({ cursor: currentSeq(db) });
});

app.use((err, _req, res, _next) => {
  console.error('[sync] unhandled:', err);
  res.status(500).json({ error: 'internal error' });
});

// --------------------------------------------------------------------- start

function lanAddresses() {
  return Object.values(networkInterfaces())
    .flat()
    .filter((n) => n && n.family === 'IPv4' && !n.internal)
    .map((n) => n.address);
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
    for (const ip of lanAddresses()) {
      console.log(`    http://${ip}:${PORT}`);
    }
  }
  console.log(`└${bar}┘\n`);
});
