# Code standards (keel base)

Each rule says why. Projects can override any of them in their own standards files.

## Correctness first
- **Handle the error or let it propagate — never swallow it.** An empty `catch` or a
  `catch` that only logs hides failures until a user reports them. (must-fix when it hides
  a failed write, payment or auth step; should-fix otherwise)
- **Async calls are awaited or explicitly fire-and-forget with error handling.** A missing
  `await` returns before the work is done and loses its errors. (must-fix)
- **Validate input at the boundary** (HTTP handlers, queue consumers, webhooks, CLI args),
  not deep inside. Internal code may trust what the boundary validated.
- **No time bombs:** hard-coded dates, temporary flags with no removal note, `TODO` on a
  code path that ships to users. Leave a ticket or a date.

## Readability
- Names say what something is in the domain (`unpaidInvoices`, not `list2`).
- A function does one thing at one level of abstraction. Long is fine if it reads top to
  bottom; deep nesting is not — return early.
- Comments explain *why*, not *what*. Delete commented-out code; git remembers it.
- Match the existing style of the file and the project before your own preferences.

## Change hygiene
- One change per PR. Refactors and behavior changes in separate commits at least, so the
  behavior change can be reviewed and reverted on its own.
- Don't leave debug output (`console.log`, `print`, `dd()`) in shipped code paths.
- New dependencies need a reason: maintained, license compatible, not 300 KB for one
  function. Prefer the standard library or what the project already uses.

## Performance (only where it matters)
- No queries inside loops over unbounded collections (N+1). (should-fix)
- Paginate anything that lists user-generated data.
- Don't optimize without a measurement; do flag obvious O(n²) over user-sized data.
