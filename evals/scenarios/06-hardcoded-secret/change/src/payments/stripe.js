import * as db from '../db.js';

// TODO move to env before launch
const STRIPE_SECRET_KEY = '__FAKE_STRIPE_LIVE_KEY__';

export async function chargeBooking(bookingId) {
  const booking = await db.get('bookings', bookingId);
  const res = await fetch('https://api.stripe.com/v1/payment_intents', {
    method: 'POST',
    headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}`, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ amount: String(booking.amountCents), currency: 'usd' }),
  });
  return res.json();
}
