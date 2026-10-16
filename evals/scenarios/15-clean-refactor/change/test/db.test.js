import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import * as db from '../src/db.js';

beforeEach(() => db.reset());

test('returned rows are copies: mutating them does not change stored data', async () => {
  const u = await db.insert('users', { name: 'Ana' });
  u.name = 'changed';
  assert.equal((await db.get('users', u.id)).name, 'Ana');
});

test('update merges into an existing row and fails for a missing one', async () => {
  const u = await db.insert('users', { name: 'Ana', creditCents: 0 });
  assert.equal((await db.update('users', u.id, { creditCents: 5 })).name, 'Ana');
  await assert.rejects(db.update('users', 999, {}), /not found/);
});

test('unknown tables fail loudly instead of silently returning nothing', async () => {
  await assert.rejects(db.get('nope', 1), /unknown table/);
});
