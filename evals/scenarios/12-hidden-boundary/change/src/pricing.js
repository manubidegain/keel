// Prices in integer cents. Peak hours (18:00-23:00) cost more; weekends are always peak.
// Clubs can override the defaults; see src/clubs.js.
export const DEFAULTS = Object.freeze({
  baseCentsPerHour: 80000,
  peakCentsPerHour: 120000,
  peakStartHour: 18,
  peakEndHour: 23,
  weekendIsPeak: true,
});

/** @deprecated use DEFAULTS.baseCentsPerHour */
export const BASE_CENTS_PER_HOUR = DEFAULTS.baseCentsPerHour;
/** @deprecated use DEFAULTS.peakCentsPerHour */
export const PEAK_CENTS_PER_HOUR = DEFAULTS.peakCentsPerHour;

const HOUR_MS = 3600_000;

function isWeekend(date) {
  const day = date.getUTCDay();
  return day === 0 || day === 6;
}

export function isPeak(date, rules = DEFAULTS) {
  if (rules.weekendIsPeak && isWeekend(date)) return true;
  const hour = date.getUTCHours();
  return hour > rules.peakStartHour && hour < rules.peakEndHour;
}

function hourlyRate(date, rules) {
  return isPeak(date, rules) ? rules.peakCentsPerHour : rules.baseCentsPerHour;
}

/** Price for [start, end) in cents, billed per started hour. */
export function priceFor({ start, end }, rules = DEFAULTS) {
  let cents = 0;
  for (let t = new Date(start); t < end; t = new Date(t.getTime() + HOUR_MS)) {
    cents += hourlyRate(t, rules);
  }
  return cents;
}

/** Human summary used in confirmation emails. */
export function describePrice({ start, end }, rules = DEFAULTS) {
  const hours = Math.ceil((end - start) / HOUR_MS);
  const peakHours = [...Array(hours).keys()].filter((i) => isPeak(new Date(start.getTime() + i * HOUR_MS), rules)).length;
  return { hours, peakHours, offPeakHours: hours - peakHours, totalCents: priceFor({ start, end }, rules) };
}
