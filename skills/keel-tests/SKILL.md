---
name: keel-tests
description: Write tests that actually protect something — chosen by risk and behavior, never by coverage, and each one proven useful by breaking the code it guards and confirming the test fails. Also finds useless, flaky or over-mocked tests worth deleting. Use when the user asks to "add tests", "write tests for this", "what should we test", "improve our tests", "add a regression test", after fixing a bug, or when keel-check reports risky code without tests. Prefer this over generating tests ad hoc, even if the user doesn't mention keel.
---

# keel-tests

AI-generated tests tend to mirror the implementation, assert what the code already does
(bugs included) and break on every refactor. This skill exists to avoid that. Fewer,
better tests.

Read `references/test-value.md` once before writing the first test in a session.

## Steps

1. **Find what's worth protecting.** From the diff (or the area the user names), list the
   behaviors that would hurt if they broke. Rank by risk: money, auth/permissions, data
   writes, business rules, edge cases, then the rest. Sources for "expected behavior", in
   order: the user, the ticket/PR description, docs, a bug that happened, the code (last —
   the code may be the bug).

2. **Check what already exists.** Find the existing tests for that area. Learn the
   project's framework, helpers, fixtures, naming and folder layout, and copy that style.
   Skip behaviors already covered by a meaningful test.

3. **Propose before writing** (skip if the user said "just write them"): a short list,
   each line = behavior protected + why it matters. Max ~5 per round. Say what you are
   deliberately *not* testing and why (trivial getters, framework code, wiring).

4. **Write the tests** through the public interface. Mock only network, clock, randomness
   and paid/external services. Use realistic data and real edge cases.

5. **Prove each test is useful — the mutation check.** For every new test:
   - Run it: it must pass. Use `bash scripts/run.sh test` or the narrowest command that runs
     just that file.
   - Break the behavior it protects with a small, plausible bug (flip a condition, drop
     a check, off-by-one, return early). Change the source in place.
   - Run it again: it **must fail**. Then restore the source exactly (`git diff` must show
     only the test files afterwards).
   - If it still passes with the bug, the test protects nothing: fix it or delete it.
   Report the result per test: `✓ fails when <bug> is introduced`.

6. **Bug fixes:** write the regression test first and show it failing on the current
   code, then apply/keep the fix and show it passing.

7. **Spot dead weight** in the files you touched: tests that never assert anything
   meaningful, assert mock calls only, snapshot huge blobs, or are flaky. Suggest deleting
   or rewriting them — don't do it without asking.

## Output

```
keel-tests · 3 tests added (src/booking/__tests__/reserve.test.ts)
✓ rejects a booking for a court already taken — fails if the overlap check is removed
✓ allows back-to-back bookings (end == start) — fails with an off-by-one in the overlap
✓ refunds credit when an admin cancels — fails if the refund call is skipped
not tested on purpose: mapper functions (pure data reshaping, covered by the above)
suggested removal: reserve.old.test.ts asserts only that mocks were called
```

## Never

- Write a test whose only purpose is coverage.
- Assert the current output of buggy code as "expected".
- Leave a mutation in the source. Always verify the source is restored.
- Weaken an existing assertion to make a test pass.
