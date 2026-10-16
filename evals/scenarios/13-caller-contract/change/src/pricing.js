// Prices per hour. Peak hours (18:00-23:00) cost more; weekends are always peak.
// Returned in dollars so the frontend can show them directly.
export const BASE_PER_HOUR = 800;
export const PEAK_PER_HOUR = 1200;

function isPeak(date) {
  const day = date.getUTCDay();
  const hour = date.getUTCHours();
  return day === 0 || day === 6 || (hour >= 18 && hour < 23);
}

export function priceFor({ start, end }) {
  let total = 0;
  for (let t = new Date(start); t < end; t = new Date(t.getTime() + 3600_000)) {
    total += isPeak(t) ? PEAK_PER_HOUR : BASE_PER_HOUR;
  }
  return total;
}
