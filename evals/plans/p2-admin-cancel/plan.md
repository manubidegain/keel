# Admin cancellations
1. In `src/bookings.js` `cancel()`, skip the owner check when the caller is an admin (`isAdmin(userId)`).
2. Admin cancellations refund exactly like normal ones, so no change there.
3. Tests: an admin can cancel someone else's booking.
