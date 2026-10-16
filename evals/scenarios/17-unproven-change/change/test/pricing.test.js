import { test } from 'node:test';
import assert from 'node:assert/strict';
import { priceFor } from '../src/pricing.js';

const at = (h) => new Date(Date.UTC(2026, 9, 14, h)); // a Wednesday

test('daytime hours are off-peak', () => {
  assert.equal(priceFor({ start: at(10), end: at(11) }), 80000);
});
