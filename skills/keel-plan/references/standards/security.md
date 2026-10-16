# Security standards (keel base)

## Secrets
- **No secrets in the repo**, including tests, fixtures, examples and history. Use env
  vars or a secret manager. A committed secret must be **rotated**, not just deleted.
  (must-fix, escalates to critical)
- `.env*` files with real values are gitignored; commit only `.env.example` with placeholders.
- Never log tokens, passwords, full card numbers, or session IDs.

## Auth and permissions
- Every endpoint/action that reads or writes user data checks **who** is calling and
  **whether they may touch this specific record** (not just "is logged in"). Missing
  object-level authorization is the most common serious bug. (must-fix)
- Authorization is enforced server-side. Hiding a button is not access control.
- Row-level security / policies: a new table that holds user data has policies from day one.
- Tokens expire; refresh tokens rotate; password reset links are single-use and short-lived.
- Rate-limit login, signup, password reset, OTP and anything that sends email/SMS.

## Input and output
- Parameterized queries / ORM bindings only. No string-built SQL with user input. (must-fix)
- Escape output by default; any `dangerouslySetInnerHTML`/`v-html`/`|safe` needs a reason.
- Uploaded files: check type and size server-side, store outside the web root, never
  execute or serve them with a guessable path.
- Redirect targets from user input are validated against an allowlist (open redirects).
- Outbound requests to user-supplied URLs are restricted (SSRF).

## Webhooks and integrations
- Verify webhook signatures; reject unsigned or stale events.
- Webhook handlers are idempotent — providers retry.

## Dependencies
- No packages with known critical vulnerabilities in production dependencies.
- Pin versions via a lockfile; review what a major upgrade changes.
