import * as db from '../db.js';

/** Runs every 15 min: email users whose booking starts in the next 2 hours. */
export async function sendReminders(now, sendEmail) {
  const soon = new Date(now.getTime() + 2 * 3600_000);
  const bookings = await db.where('bookings', (b) => b.status === 'confirmed' && b.start > now && b.start <= soon);
  let sent = 0;
  for (const b of bookings) {
    try {
      const user = await db.get('users', b.userId);
      await sendEmail(user.email, `Your court is booked at ${b.start.toISOString()}`);
      sent++;
    } catch (e) {}
  }
  return sent;
}
