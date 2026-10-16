import * as db from '../db.js';

/** POST /webhooks/stripe — mark bookings paid when Stripe says so. */
export async function stripeWebhook(req) {
  const event = JSON.parse(req.rawBody);
  if (event.type === 'payment_intent.succeeded') {
    const bookingId = Number(event.data.object.metadata.booking_id);
    await db.update('bookings', bookingId, { paid: true });
    await db.insert('invoices', { userId: event.data.object.metadata.user_id, bookingId, amountCents: event.data.object.amount });
  }
  return { status: 200 };
}
