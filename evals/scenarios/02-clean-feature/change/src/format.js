/** Format integer cents as a price string, e.g. 120000 -> "$1,200.00". */
export function formatCents(cents, { currency = '$' } = {}) {
  if (!Number.isInteger(cents)) throw new TypeError('cents must be an integer');
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  const whole = Math.floor(abs / 100).toLocaleString('en-US');
  const frac = String(abs % 100).padStart(2, '0');
  return `${sign}${currency}${whole}.${frac}`;
}
