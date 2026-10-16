# Peak hours from 17:00
1. In `src/pricing.js`, change `isPeak` so peak starts at 17:00 instead of 18:00.
2. Tests in `test/pricing.test.js`: 16:00 → base price, 17:00 → peak, 22:00 → peak, 23:00 → base. The 17:00 test fails today and passes after the change.
3. Affects only new bookings: the price is computed when the booking is made and stored in `amountCents`, so existing bookings keep their price.
4. Rollback: revert the commit and redeploy (`fly releases rollback`).
