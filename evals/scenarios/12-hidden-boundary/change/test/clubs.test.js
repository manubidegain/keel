import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateRules } from '../src/clubs.js';
import { DEFAULTS } from '../src/pricing.js';

test('defaults are valid', () => {
  assert.deepEqual(validateRules(DEFAULTS), []);
});

test('rejects negative prices and inverted peak windows', () => {
  assert.equal(validateRules({ ...DEFAULTS, baseCentsPerHour: -1 }).length, 1);
  assert.equal(validateRules({ ...DEFAULTS, peakStartHour: 23, peakEndHour: 18 }).length, 1);
});
