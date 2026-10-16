# What makes a test valuable

A test is valuable in proportion to: (how likely the behavior is to break) ×
(how bad it is if it breaks) × (how likely this test is to catch it) − (cost to maintain it).

## Checklist for every test

- [ ] I can name the breakage it catches in one sentence.
- [ ] It fails if that behavior breaks (proven by the mutation check).
- [ ] It does not fail if the code is refactored without changing behavior.
- [ ] It uses the public interface (function exported, endpoint, UI as a user sees it).
- [ ] Its expected values come from the requirement, not from running the code.
- [ ] It is deterministic: no real time, network, randomness or ordering assumptions.
- [ ] Its name reads as a specification.
- [ ] It looks like the other tests in this project.

## Good targets

- Business rules with conditions (pricing, eligibility, limits, state transitions).
- Authorization: user A cannot read/modify user B's record.
- Boundaries: 0, 1, max, empty, duplicate, exactly-at-the-limit, end of month, DST, leap day.
- Money: rounding, currency, refunds, partial payments.
- Idempotency: the same webhook/job twice does not double-charge or double-create.
- Every bug that already happened.

## Poor targets

- Getters/setters, constants, type definitions, framework wiring, re-exports.
- Pure pass-through functions already exercised by a higher-level test.
- Exact copies of the implementation's logic in the test ("tautological tests").
- Snapshot tests of large structures nobody reads in review.

## Mutation check — plausible bugs to introduce

| Code shape | Mutation |
|---|---|
| `if (a > b)` | `>=`, `<`, or remove the condition |
| permission / ownership check | delete it or invert it |
| `return x` after validation | return before validation |
| loop bounds | off by one |
| `await save()` | remove the call |
| sum / price calc | drop a term, swap rounding |
| idempotency key check | skip it |

One mutation per test is enough. If the test survives a mutation of the very thing it
claims to protect, rewrite it.
