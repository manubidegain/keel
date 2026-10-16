// Prices in integer cents. Peak hours (17:00-23:00) cost more; weekends are always peak.
export const BASE_CENTS_PER_HOUR = 80000;
export const PEAK_CENTS_PER_HOUR = 120000;

function isPeak(date) {
  const day = date.getUTCDay();
  const hour = date.getUTCHours();
  return day === 0 || day === 6 || (hour >= 17 && hour < 23);
}

// TODO handle half hours
export function priceFor({ start, end }) {
  let cents = 0;
  for (let t = new Date(start); t < end; t = new Date(t.getTime() + 3600_000)) {
    cents += isPeak(t) ? PEAK_CENTS_PER_HOUR : BASE_CENTS_PER_HOUR;
  }
  console.log("price", cents);
  return cents;
}
