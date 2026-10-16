import { test } from 'node:test';
import assert from 'node:assert/strict';
import { priceFor } from '../src/pricing.js';

const at = (h) => new Date(Date.UTC(2026, 9, 14, h)); // a Wednesday

test('peak starts at 17:00 on weekdays', () => {
  assert.equal(priceFor({ start: at(16), end: at(17) }), 80000);
  assert.equal(priceFor({ start: at(17), end: at(18) }), 120000);
});

test('peak still ends at 23:00', () => {
  assert.equal(priceFor({ start: at(22), end: at(23) }), 120000);
  assert.equal(priceFor({ start: at(23), end: at(24) }), 80000);
});
