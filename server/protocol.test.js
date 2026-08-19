// The wire version. Run with: npm run test:server
//
// There is not much logic here to test - the value of the number is a decision,
// not a computation - but there is one invariant, and it is the kind that gets
// broken by a hurried edit rather than by a misunderstanding.

import test from 'node:test';
import assert from 'node:assert/strict';

import { MIN_CLIENT, PROTOCOL } from './protocol.js';

test('both numbers are whole and start at 1', () => {
  // 1 is the floor because 1 is what the wire was on the day the number was
  // invented: every server and client that predates the handshake sends
  // nothing and is read as 1, so there is no 0 for anything to mean.
  assert.ok(Number.isInteger(PROTOCOL), 'PROTOCOL must be an integer');
  assert.ok(Number.isInteger(MIN_CLIENT), 'MIN_CLIENT must be an integer');
  assert.ok(PROTOCOL >= 1);
  assert.ok(MIN_CLIENT >= 1);
});

test('the server does not demand a client newer than itself', () => {
  // MIN_CLIENT > PROTOCOL would be a server refusing every client that speaks
  // exactly the wire it speaks - including the one shipped alongside it. It is
  // an easy thing to typo when bumping both in the same edit, and it locks
  // every device out of the deployment at once.
  assert.ok(
    MIN_CLIENT <= PROTOCOL,
    `MIN_CLIENT (${MIN_CLIENT}) cannot exceed PROTOCOL (${PROTOCOL}) - that ` +
      'refuses the client that speaks this very wire',
  );
});
