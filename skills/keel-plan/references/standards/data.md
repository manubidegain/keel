# Data and migration standards (keel base)

## Migrations
- **Every migration is reversible or says explicitly why it isn't.** If it isn't, the PR
  includes a backup step or a two-phase plan. (must-fix for DROP/TRUNCATE/destructive RENAME)
- **Expand → migrate → contract.** To rename or remove a column: add the new one, deploy
  code that writes both / reads new, backfill, deploy code that stops using the old one,
  then drop it in a later release. Old app versions (especially mobile) keep running.
- Adding a NOT NULL column to an existing table needs a default or a backfill first.
- Large tables: create indexes concurrently / online; batch backfills; avoid long locks.
- Migrations are tested against realistic data size and shape, not just an empty database.
- Never edit a migration that already ran in a shared environment; add a new one.

## Integrity
- Money is stored as integers in minor units (cents) or a decimal type — never floats.
- Writes that must happen together run in one transaction.
- Anything retried (jobs, webhooks, payments) is idempotent — use idempotency keys.
- Timestamps are stored in UTC with time zone; converted at the edges.

## Personal data
- Collect only what the feature needs. Each new personal field has a reason.
- Real user data never goes to local machines, fixtures, logs, analytics or AI prompts
  without anonymization.
- Deleting an account deletes (or anonymizes) the person's data everywhere it was copied.
