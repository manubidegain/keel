# Testing standards (keel base)

Tests exist to catch breakage that matters. Coverage is a signal, never a goal.

- **Test behavior, not implementation.** A test should survive a refactor that keeps
  behavior the same, and fail when behavior breaks.
- **Every test protects something nameable.** If you can't say in one sentence which
  breakage it catches, it shouldn't exist.
- **Risk decides what gets tested first:** money, auth/permissions, data writes, business
  rules, edge cases (empty, zero, limits, time zones, duplicates, concurrency), then the rest.
- **Every bug fix ships with a regression test** that fails without the fix.
- **Prefer real collaborators over mocks.** Mock only what is slow, non-deterministic or
  external (network, clock, payment provider). Asserting that an internal method was
  called is usually testing implementation.
- **E2E tests only for flows that cost money or trust when broken** (signup/login,
  checkout, booking, payment). Everything else lower in the pyramid.
- **Deterministic:** no real network, no sleeps, fixed clock and seeds. A flaky test is a
  bug: fix or delete it, don't retry it forever.
- **Readable as a spec:** the name states the behavior (`rejects a booking for a court
  already taken`), one reason to fail, arrange/act/assert visible.
- Deleting a useless test is an improvement, even if coverage drops.

For writing new tests, use the `keel-tests` skill.
