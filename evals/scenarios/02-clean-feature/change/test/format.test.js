import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatCents } from '../src/format.js';

test('formats whole and fractional cents with thousands separators', () => {
  assert.equal(formatCents(120000), '$1,200.00');
  assert.equal(formatCents(5), '$0.05');
});

test('keeps the sign for negative amounts (refunds)', () => {
  assert.equal(formatCents(-2550), '-$25.50');
});

test('rejects non-integer cents so floats never reach the UI', () => {
  assert.throws(() => formatCents(10.5), TypeError);
});
