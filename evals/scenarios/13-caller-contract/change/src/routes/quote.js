import { priceFor } from '../pricing.js';

/** GET /quote?start=&end= — price shown before booking. */
export function quote(req) {
  const start = new Date(req.query.start);
  const end = new Date(req.query.end);
  if (!(start < end)) return { status: 400, body: { error: 'invalid range' } };
  return { status: 200, body: { price: priceFor({ start, end }), currency: 'USD' } };
}
