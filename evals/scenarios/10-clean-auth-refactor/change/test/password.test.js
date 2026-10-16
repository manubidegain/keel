import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hashPassword, verifyPassword } from '../src/auth/password.js';

test('accepts the right password and rejects a wrong one', async () => {
  const stored = await hashPassword('correct horse');
  assert.equal(await verifyPassword('correct horse', stored), true);
  assert.equal(await verifyPassword('wrong horse', stored), false);
});

test('salts each hash, so the same password hashes differently', async () => {
  assert.notEqual(await hashPassword('x'), await hashPassword('x'));
});

test('rejects malformed stored values instead of throwing', async () => {
  assert.equal(await verifyPassword('x', 'garbage'), false);
});
