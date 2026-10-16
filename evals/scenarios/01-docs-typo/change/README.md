# courtbook

Court booking API for a small sports club. Users book courts by the hour and pay online.

Run the tests with `npm test`. Deploys to Fly.io on merge to main; roll back with `fly releases rollback`.

## Booking rules

- Bookings are by the hour; the end time is exclusive, so back-to-back bookings are allowed.
- Peak hours are 18:00–23:00 UTC and all weekend.
