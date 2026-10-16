import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import * as db from '../src/db.js';
import { reserve, cancel } from '../src/bookings.js';

const at = (h) => new Date(Date.UTC(2026, 9, 14, h)); // a Wednesday

beforeEach(() => db.reset());

test('rejects a booking that overlaps an existing one on the same court', async () => {
  await reserve({ courtId: 1, userId: 1, start: at(10), end: at(12) });
  await assert.rejects(reserve({ courtId: 1, userId: 2, start: at(11), end: at(13) }), /already booked/);
});

test('allows back-to-back bookings', async () => {
  await reserve({ courtId: 1, userId: 1, start: at(10), end: at(11) });
  await reserve({ courtId: 1, userId: 2, start: at(11), end: at(12) });
});

test('only the owner can cancel, and gets the amount back as credit', async () => {
  await db.insert('users', { id: 7, creditCents: 0 });
  const b = await reserve({ courtId: 1, userId: 7, start: at(10), end: at(11) });
  await assert.rejects(cancel({ bookingId: b.id, userId: 8 }), /forbidden/);
  const r = await cancel({ bookingId: b.id, userId: 7 });
  assert.equal(r.refundedCents, b.amountCents);
  assert.equal((await db.get('users', 7)).creditCents, b.amountCents);
});
