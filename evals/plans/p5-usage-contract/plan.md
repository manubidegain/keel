# Bookings API: price in dollars
1. `GET /api/bookings/:id` returns `price` (dollars, e.g. 12.5) instead of `amountCents`.
2. Update `src/bookings.js` to convert with `amountCents / 100` when building the response.
3. Tests: the response has `price` with the right value.
4. Rollback: revert the commit.
