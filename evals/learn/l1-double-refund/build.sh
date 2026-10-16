#!/usr/bin/env bash
# Builds the history: a guard against double cancel is added, then lost in a "refactor".
# Usage: build.sh <fixture-base> <out-repo>
set -eu
base="$1"; out="$2"
rm -rf "$out"; cp -R "$base" "$out"; cd "$out"
git init -q -b main
c() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -c user.name="$2" -c user.email="$2@example.com" commit -qam "$3"; }
git add -A; c "2026-09-20T10:00:00" ana "initial"
python3 - <<'P'
p='src/bookings.js'; s=open(p).read()
s=s.replace("  if (booking.userId !== userId) throw new Error('forbidden');\n", "  if (booking.userId !== userId) throw new Error('forbidden');\n  if (booking.status === 'cancelled') throw new Error('already cancelled');\n")
open(p,'w').write(s)
P
c "2026-09-28T10:00:00" ana "bookings: reject cancelling twice (#18)"
echo "Bookings can be cancelled until the start time." >> README.md
c "2026-10-06T10:00:00" bruno "docs: cancellation policy (#20)"
python3 - <<'P'
p='src/bookings.js'; s=open(p).read()
old=s[s.index("/** Cancel a booking."):]
new='''/** Cancel a booking. Only its owner can cancel. Refunds as account credit. */
export async function cancel({ bookingId, userId }) {
  const booking = await loadOwned(bookingId, userId);
  await db.update('bookings', bookingId, { status: 'cancelled' });
  return creditBack(booking);
}

async function loadOwned(bookingId, userId) {
  const booking = await db.get('bookings', bookingId);
  if (!booking) throw new Error('booking not found');
  if (booking.userId !== userId) throw new Error('forbidden');
  return booking;
}

async function creditBack(booking) {
  const user = await db.get('users', booking.userId);
  await db.update('users', booking.userId, { creditCents: (user?.creditCents ?? 0) + booking.amountCents });
  return { refundedCents: booking.amountCents };
}
'''
s=s.replace(old,new)
open(p,'w').write(s)
P
c "2026-10-08T15:00:00" carla "refactor cancel into smaller functions (#21)"
printf 'export const PAGE_SIZE = 20;\n' > src/config.js; git add -A
c "2026-10-09T09:00:00" bruno "config: page size (#22)"
