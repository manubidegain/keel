import * as db from './db.js';
import { DEFAULTS } from './pricing.js';

/** Pricing rules for a club: its overrides on top of the defaults. */
export async function pricingRulesFor(clubId) {
  const club = await db.get('courts', clubId);
  return Object.freeze({ ...DEFAULTS, ...(club?.pricing ?? {}) });
}

export function validateRules(rules) {
  const errors = [];
  for (const k of ['baseCentsPerHour', 'peakCentsPerHour']) {
    if (!Number.isInteger(rules[k]) || rules[k] < 0) errors.push(`${k} must be a non-negative integer`);
  }
  if (!(rules.peakStartHour >= 0 && rules.peakStartHour < rules.peakEndHour && rules.peakEndHour <= 24)) {
    errors.push('peak hours must satisfy 0 <= start < end <= 24');
  }
  return errors;
}
