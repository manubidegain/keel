# Tiers — what each risk level requires

`scripts/risk.sh` assigns the tier. The policy file can override `require` and
`review_until` per tier. These are the defaults.

| Tier | Typical change | Checks to run | Review depth | Iterate until |
|---|---|---|---|---|
| **low** | docs, copy, styles, small internal code | `test` if code changed, `lint` | quick pass over the diff for obvious bugs | no must-fix |
| **medium** | new feature behind a flag, deps bump, jobs/notifications, big diffs, code without tests | `test`, `lint`, `typecheck` | full diff against the relevant standards | no must-fix; should-fix fixed or listed |
| **high** | auth, permissions, payments, migrations, infra/CI, env, public API, policy-sensitive paths | `test`, `lint`, `typecheck`, `build`, `e2e` if configured | full diff + read callers of changed functions + security and data standards | no must-fix and no should-fix (or waived with a reason) |
| **critical** | irreversible data ops, possible secret, high-risk change during a freeze | everything above | everything above + rollback plan written + owner named | nothing open; owner acknowledgement required before merge/deploy |

## Severity definitions

- **must-fix** — will cause a bug, a security hole, data loss, a broken build/deploy, or
  violates a rule the policy marks as mandatory. Merge should not happen with it open.
- **should-fix** — real problem with lower odds or impact: missing test for a risky path,
  error swallowed, unclear naming in a public API, N+1 query, missing index.
- **nit** — style or taste. Hidden by default (`review.nits: false`). Never block on nits.

When unsure between two severities, pick the lower one and say why in one line.
False alarms cost more trust than a missed nit.

## Iteration budget

Each "iteration" = fix → re-run the failed checks → re-review only what changed.

| Tier | Max iterations before stopping to ask the user |
|---|---|
| low | 1 |
| medium | 2 |
| high | 3 |
| critical | 3, and always ask before declaring done |

If the budget runs out with must-fix items still open, stop, list them, and ask whether
to keep going, waive (with reason), or split the change.

## Escalation rules (always apply, regardless of tier)

- A possible secret in the diff → stop everything else. Tell the user to remove it **and
  rotate it**; removing the line is not enough once it was committed or pushed.
- An irreversible operation (DROP/TRUNCATE/DELETE/RENAME on data) → require a written
  rollback or backup step before calling it done.
- High/critical change and `rollback:` missing from the policy → ask how it would be undone.
