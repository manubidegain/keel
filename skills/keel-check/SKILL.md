---
name: keel-check
description: Risk-aware pre-commit/pre-PR check for any repository. Classifies the current change as low/medium/high/critical from its diff, runs only the checks that tier needs (tests, lint, typecheck, build, e2e), reviews the diff against the project's standards, fixes the simple problems itself, asks only about what needs judgment, and prepares the PR description. Use whenever the user says "keel", "check this", "is this ready?", "can I commit/push/merge?", "review my changes", "pre-commit check", "run the checks", or finishes a coding task and is about to commit or open a PR — even if they don't name keel.
---

# keel-check

A senior teammate looking over the change before it ships: fast on small changes, thorough
on risky ones, and useful — it fixes and prepares things, it does not just complain.

## Speed contract

- Low tier: one short answer, no questions, done in well under a minute of tool time.
- Never ask what a script, the diff, or the policy file can answer.
- Mechanical work (diffs, commands, logs) goes through the scripts; reasoning is spent
  only on the review itself.

## Steps

1. **Classify.** From the repo root run `bash scripts/risk.sh` (path relative to this
   skill's folder). It diffs against the merge-base with main/master, including uncommitted
   and untracked files, and prints the tier and why. Use `--base <ref>` if the user names a
   base. If there is no diff, say so and stop.

2. **Load only what the tier needs.**
   - Policy: `.agents/keel.yaml` if present (overrides defaults). No policy → defaults; do
     not stop to create one (mention `keel-setup` once at the end, only if tier ≥ medium).
     If it has `extends:`, read that file too (local path, or raw file from the git host);
     the project's values win. If `tiers:` overrides requirements, use those.
   - Freeze: if the current local time is inside a `freeze:` window and the tier is high,
     treat it as critical.
   - `references/tiers.md` — required checks, review depth, iteration budget.
   - Standards: for low tier skip them. Otherwise read only the files in
     `references/standards/` that match the reasons (auth/secrets → `security.md`,
     migrations → `data.md`, tests missing → `testing.md`, CI/infra → `release.md`, any code →
     `code.md`), plus project/org standards listed under `standards:` in the policy.
     Project standards win over keel's when they conflict.

3. **Run checks** for the tier: `bash scripts/run.sh test lint typecheck …`. It prints
   ✓/✗ per check and the tail of failures; full logs are in `.keel/logs/`. Don't re-run
   passing checks in later iterations.

4. **Review the diff** at the depth the tier requires. Look for real problems only: bugs,
   security, data integrity, error handling, breaking changes, missing tests on risky paths,
   standards violations. For high/critical, also read the callers of changed functions.
   Classify each finding as must-fix / should-fix / nit (definitions in `tiers.md`).

5. **Fix what is safe to fix** without asking: failing lint/format, unused imports, obvious
   typos, a missing `await`, a test that fails because of a trivial mismatch you can prove.
   Ask before anything that changes behavior, deletes code, or touches a sensitive area.
   Never weaken or delete a test to make it pass.

6. **Iterate** within the tier's budget: re-run only failed checks, re-review only what
   changed. Stop when the tier's "iterate until" is met, or the budget is spent (then ask).

7. **Prepare the PR** when the result is ready to ship: write `.keel/pr.md` with a title,
   what changed and why (from the diff and the conversation, never invented), the risk tier
   and why, how it was tested, and — for high/critical — the rollback plan. Offer to open
   the PR if a GitHub CLI or connector is available; don't open it unasked.

8. **Tests.** If the tier is ≥ medium and risky code changed without tests, say which
   behavior is unprotected in one line and offer `keel-tests`. Do not generate coverage-only
   tests here.

## Output format

Keep it this short. Use the user's language.

```
keel · HIGH — touches src/auth/session.ts, adds a migration
✓ test  ✓ lint  ✓ typecheck  ✗ build
must-fix
  1. session.ts:42 — refresh token never expires; a stolen token works forever
should-fix
  2. 004_add_index.sql — CREATE INDEX without CONCURRENTLY locks the table on big tables
fixed for you
  · removed 2 unused imports · fixed build error (missing export in auth/index.ts)
next: fix #1 (want me to?) · PR description ready in .keel/pr.md
```

When everything passes on a low tier: `keel · LOW — docs only. ✓ Ready.` and nothing more.

## Waivers

If the user decides to ship with an open must-fix or should-fix, don't argue twice. Record
it in `.agents/keel-waivers.md` (committed): date, finding, who decided, why, and an
expiry or follow-up ticket. Mention it in the PR description.

## Never

- Block on nits, or report more than ~10 findings at once (prioritize; mention the count of the rest).
- Invent test results, commands, or PR content you didn't verify.
- Run destructive commands (migrations against real databases, deploys, `git push --force`).
- Print secret values found in the diff — name the file and line only.
