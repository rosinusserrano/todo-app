import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import Database from 'better-sqlite3';

import { BlobError, getBlob, initBlobs, putBlob } from './blobs.js';

function db() {
  const d = new Database(':memory:');
  initBlobs(d);
  return d;
}

const bytes = Buffer.from('not really opus');
const digest = createHash('sha256').update(bytes).digest('hex');

test('a blob is kept under its digest, per account, with its type', () => {
  const d = db();
  assert.equal(putBlob(d, 'u1', digest, 'audio/webm;codecs=opus', bytes), true);
  const got = getBlob(d, 'u1', digest);
  assert.equal(got.type, 'audio/webm;codecs=opus');
  assert.deepEqual(Buffer.from(got.data), bytes);
  assert.equal(getBlob(d, 'u2', digest), null, 'another account cannot read it');
});

test('putting it again is a no-op, so a retry is safe', () => {
  const d = db();
  putBlob(d, 'u1', digest, 'audio/mp4', bytes);
  assert.equal(putBlob(d, 'u1', digest, 'audio/mp4', bytes), false);
});

test('bytes that do not hash to the name are refused', () => {
  const d = db();
  assert.throws(
    () => putBlob(d, 'u1', digest, 'audio/mp4', Buffer.from('something else')),
    (e) => e instanceof BlobError && e.status === 400,
  );
  assert.throws(() => putBlob(d, 'u1', 'nope', 'audio/mp4', bytes), BlobError);
  assert.throws(() => putBlob(d, 'u1', digest, 'audio/mp4', Buffer.alloc(0)), BlobError);
  assert.equal(getBlob(d, 'u1', digest), null);
});

test('a type that is not a type is stored as the generic one', () => {
  const d = db();
  putBlob(d, 'u1', digest, 'audio/mp4\r\nX-Evil: 1', bytes);
  assert.equal(getBlob(d, 'u1', digest).type, 'application/octet-stream');
});
