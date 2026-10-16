# Release, CI and operations standards (keel base)

## Before shipping a high/critical change
- **Rollback written down:** how to undo it and how long it takes. If the change can't be
  undone (data migration, sent emails, charged cards), say what the recovery plan is.
- Ship behind a feature flag when the change is user-visible and risky; default off.
- Prefer gradual rollout (canary, % of users) when the platform supports it.
- Don't ship high-risk changes into a freeze window or when nobody can watch the result.

## After shipping
- Watch the signals that would show the change failing (errors, the affected flow's
  success rate) for a period proportional to the risk — minutes for low, an hour or more
  for critical.
- Decide the rollback trigger before deploying, not while looking at a graph.

## CI/CD and infrastructure
- CI config changes are reviewed like code: they can leak secrets or deploy the wrong thing.
- Workflows that run on pull requests from forks must not have access to secrets.
- Third-party actions/images are pinned to a version or digest.
- Infra changes show their plan/diff (e.g. `terraform plan`) in the PR.

## Observability
- New critical paths log failures with enough context to debug (ids, not personal data).
- Errors reach an error tracker; silent failure is not acceptable for payments, auth or
  data writes.

## Git
- Small PRs (under ~400 changed lines when possible), one purpose each.
- Commit messages say why, not only what.
- Never force-push to shared branches.
