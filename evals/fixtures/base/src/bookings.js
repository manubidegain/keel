import * as db from './db.js';
import { priceFor } from './pricing.js';

/** Book a court. start/end are Date objects; end is exclusive. */
export async function reserve({ courtId, userId, start, end }) {
  if (!(start < end)) throw new Error('start must be before end');
  const overlapping = await db.where(
    'bookings',
    (b) => b.courtId === courtId && b.status !== 'cancelled' && b.start < end && start < b.end,
  );
  if (overlapping.length > 0) throw new Error('court already booked');
  const amountCents = priceFor({ start, end });
  return db.insert('bookings', { courtId, userId, start, end, amountCents, status: 'confirmed' });
}

/** Cancel a booking. Only its owner can cancel. Refunds as account credit. */
export async function cancel({ bookingId, userId }) {
  const booking = await db.get('bookings', bookingId);
  if (!booking) throw new Error('booking not found');
  if (booking.userId !== userId) throw new Error('forbidden');
  await db.update('bookings', bookingId, { status: 'cancelled' });
  const user = await db.get('users', userId);
  await db.update('users', userId, { creditCents: (user?.creditCents ?? 0) + booking.amountCents });
  return { refundedCents: booking.amountCents };
}
