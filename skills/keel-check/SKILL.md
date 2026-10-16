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
   - Standards: for low tier skip them. Otherwise read `references/standards/contribution.md`
     (proven work — applies to every medium+ change) and only the other files in
     `references/standards/` that match the reasons (auth/secrets → `security.md`,
     migrations → `data.md`, tests missing → `testing.md`, CI/infra → `release.md`, any code →
     `code.md`), plus project/org standards listed under `standards:` in the policy.
     Project standards win over keel's when they conflict.

3. **Run checks** for the tier: `bash scripts/run.sh test lint typecheck …`. It prints
   ✓/✗ per check and the tail of failures; full logs are in `.keel/logs/`. Don't re-run
   passing checks in later passes. Also, cheap and mechanical:
   - `bash scripts/slop.sh` — type escapes, suppressions, debug output, untracked TODOs,
     focused/skipped tests in the added lines. Each hit is a finding (should-fix; a
     focused test or a cast that hides a real type error is must-fix). Fix the trivial ones.
   - Medium+ with code changes: `bash scripts/prove.sh` — runs the tests with the change
     reverted in a throwaway worktree. `PROVEN` = the tests catch it. `NOT PROVEN` = they
     pass without the change: the change is untested (should-fix; must-fix on high).
     `INCONCLUSIVE` for new files = use keel-tests' mutation check. Never block on
     INCONCLUSIVE alone.

4. **Review the diff** at the depth the tier requires. Look for real problems only: bugs,
   security, data integrity, error handling, breaking changes, missing tests on risky paths,
   standards violations. For high/critical, also read the callers of changed functions.
   Classify each finding as must-fix / should-fix / nit (definitions in `tiers.md`).
   Keep the list signal-only:
   - **One finding per root cause.** "DROP COLUMN" and "no rollback for that DROP" are one finding.
   - **Only what this change introduced or made worse.** A problem that already existed in
     untouched behavior goes in one `noticed:` line at the end, never as must/should-fix.
   - **Nits are not shown** — not even as "hidden" — unless the policy sets `review.nits: true`.
   - **Missing tests are one line**, not a finding per file (see step 9).
   - **Against the plan.** If `.keel/plan.md` exists (an approved plan from keel-plan for this
     work), compare: planned steps not done, promised tests or rollback missing, or changes
     in risky areas the plan never mentioned. One `plan:` line; a missing promised rollback
     or backup on high/critical is must-fix. Done differently but better is fine — say so.

5. **Fix what is safe to fix** without asking: failing lint/format, unused imports, obvious
   typos, a missing `await`, a test that fails because of a trivial mismatch you can prove.
   Ask before anything that changes behavior, deletes code, or touches a sensitive area.
   Never weaken or delete a test to make it pass.

6. **Review again until clean.** For medium+, repeat the review of the whole change with
   fresh eyes after each round of fixes, until two consecutive passes find nothing new or
   four passes are done (`tiers.md`). Low: one pass. Count passes in the output.

7. **Ready check.** For medium+, answer the questions in `contribution.md` §4 with evidence
   (what you ran and saw). Any "no" or "not sure" → not ready: say which and what would
   settle it. Don't claim something was seen working unless it was actually run in this
   session or the user said so.

8. **Prepare the PR** when the result is ready to ship: write `.keel/pr.md` with a title,
   what changed and why (from the diff and the conversation, never invented), an
   **Evidence** section (commands run and their result, the prove.sh result, edges covered,
   what was run by hand and what it showed), and — for high/critical — the rollback plan. Write it as the user, in their voice
   (`references/voice.md`): first person, no mention of keel or AI, no attribution lines,
   no risk-tier jargon unless the team uses it. Offer to open the PR with `gh pr create`
   (their own auth, so it's under their name); don't open it unasked. Commits keel makes use
   the repo's configured git identity — never set a different author.

9. **Tests.** If the tier is ≥ medium and risky code changed without tests, add one
   `tests:` line naming the behavior that is unprotected and offer `keel-tests`. Do not
   generate coverage-only tests here.

## Output format

Keep it this short. Use the user's language.

```
keel · HIGH — touches src/auth/session.ts, adds a migration
✓ test  ✓ lint  ✓ typecheck  ✗ build  ✓ proven (tests fail without the change)  · 2 passes
must-fix
  1. session.ts:42 — refresh token never expires; a stolen token works forever
should-fix
  2. 004_add_index.sql — CREATE INDEX without CONCURRENTLY locks the table on big tables
fixed for you
  · removed 2 unused imports · fixed build error (missing export in auth/index.ts)
tests: nothing checks that an expired session is rejected — want keel-tests to add it?
plan: done as planned, except the "rotate on login" step — not in the diff
noticed: (not from this change) logout doesn't clear the refresh cookie
next: fix #1 (want me to?) · PR description ready in .keel/pr.md
```

Omit any section that would be empty (no "must-fix: none").

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
