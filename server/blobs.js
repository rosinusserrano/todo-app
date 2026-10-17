// Bytes the rows point at: a voice note's audio, for now.
//
// Rows sync through /api/sync; bytes do not belong in that body. A recording
// is a megabyte where a row is a few hundred bytes, and the merge is
// last-write-wins per row, which means nothing for a file named by its own
// contents. So a row carries the SHA-256 of its bytes (`side_thoughts.audio`,
// `tasks.audio`) and the bytes travel on their own:
//
//   PUT /api/blobs/:sha256   the body is the file; refused unless it hashes
//                            to the name. Putting one that is already here
//                            is a no-op, which is what makes a retry safe.
//   GET /api/blobs/:sha256   the file, with the type it was put with.
//
// Per account, like every row: one user cannot read another's bytes by
// guessing a digest, and purgeUser takes them with the account. Kept in the
// database rather than in a directory beside it so a backup of the one file
// is a backup of everything, and nothing about the server's layout changes.
//
// Nothing is ever deleted here except with the account. Thoughts are never
// hard-deleted either, and a voice note is a few hundred kilobytes; a
// collector would be work spent on a problem nobody has.

import { createHash } from 'node:crypto';

/** The largest file accepted: ten minutes of speech is about 2.5 MB. */
export const MAX_BLOB_BYTES = 25 * 1024 * 1024;

export function initBlobs(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS blobs (
      user_id    TEXT NOT NULL,
      sha256     TEXT NOT NULL,
      type       TEXT NOT NULL,
      size       INTEGER NOT NULL,
      data       BLOB NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, sha256)
    );
  `);
}

/** A name a blob can have: 64 lowercase hex digits. */
export function isDigest(s) {
  return typeof s === 'string' && /^[0-9a-f]{64}$/.test(s);
}

/**
 * Store [data] under [sha256] for [userId]. Throws a BlobError when the bytes
 * are not what the name says. Returns whether anything was written.
 */
export function putBlob(db, userId, sha256, type, data, now = new Date()) {
  if (!isDigest(sha256)) throw new BlobError(400, 'not a sha256');
  if (!Buffer.isBuffer(data) || data.length === 0) {
    throw new BlobError(400, 'empty body');
  }
  if (data.length > MAX_BLOB_BYTES) throw new BlobError(413, 'too large');
  const actual = createHash('sha256').update(data).digest('hex');
  if (actual !== sha256) throw new BlobError(400, 'body does not match its name');
  const result = db
    .prepare(
      `INSERT OR IGNORE INTO blobs (user_id, sha256, type, size, data, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .run(userId, sha256, cleanType(type), data.length, data, now.toISOString());
  return result.changes > 0;
}

/** The blob, or null. */
export function getBlob(db, userId, sha256) {
  if (!isDigest(sha256)) return null;
  return (
    db
      .prepare('SELECT type, data FROM blobs WHERE user_id = ? AND sha256 = ?')
      .get(userId, sha256) ?? null
  );
}

/** For purgeUser. */
export function deleteBlobsFor(db, userId) {
  db.prepare('DELETE FROM blobs WHERE user_id = ?').run(userId);
}

/**
 * A content type safe to hand back: `type/subtype` and its parameters, or the
 * generic one. It is echoed in a response header, so nothing else gets
 * through.
 */
function cleanType(type) {
  const t = String(type ?? '').trim();
  return /^[\w.+-]+\/[\w.+-]+(;\s*[\w.+-]+=[\w.+"=-]+)*$/.test(t) && t.length < 120
    ? t
    : 'application/octet-stream';
}

export class BlobError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
