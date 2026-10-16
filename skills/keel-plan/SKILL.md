---
name: keel-plan
description: Risk-aware planning before any code is written. Takes a plan (the agent's own, a pasted spec or issue, or just the request), classifies its risk from the files and operations it names, checks it against the code and the project's standards, and flags what a plan at that risk must answer — rollback, backups, who is affected, the test that proves it — before it's expensive to change. Low-risk plans get a one-line go; risky ones get a few pinned notes, optionally on the plan itself in Plannotator. Use when the user says "plan this", "let's plan", "how would we do X", "before I start", "review my plan", "keel plan", shares a spec or issue to build, or approves a plan in plan mode — even if they don't name keel.
---

# keel-plan

Catches in the plan what keel-check would catch in the diff — when fixing it costs a line
instead of a refactor. Fast on small plans, thorough on risky ones.

## Speed contract

- Low tier: one line, no questions, no notes. Planning a typo fix is overkill.
- Never ask what the code can answer: who calls an endpoint, which tables a column is in,
  whether tests exist. Look it up and put the answer in the plan.
- Questions only for what needs the user's judgment, at most 3.

## Steps

1. **Get the plan into `.keel/plan.md`.**
   - A plan already exists (yours from plan mode, a file, a pasted spec/issue) → save it
     there as is. Don't rewrite the user's plan.
   - Only a request → read the code it touches first (the files, their callers, existing
     tests and patterns), then draft a plan sized to the change:
     **Goal** (one line) · **Changes** (numbered, with file paths) · **Tests** (what fails
     without the change) · and for risky work **Rollback** and **Affects**. A small change
     gets 3–5 lines; don't pad.

2. **Classify.** `bash scripts/plan_risk.sh .keel/plan.md` (path relative to this skill). It
   reads the paths and operations the plan names, applies the project policy
   (`.agents/keel.yaml`: sensitive paths, data, freeze windows) and prints the tier, why, and
   an `answers` checklist. It's keyword-based: if you know the plan touches something risky
   that it missed (the code you read says so), raise the tier and say why in one line; never
   lower it silently.

3. **Low → go.** `keel plan · LOW — <what>. Go.` Then, if the user asked to build it, build it.
   The one exception: if the plan doesn't do what was asked, or something it relies on
   doesn't exist in the code, add it in one line after "Go." (`· there's no start script —
   "start locally" needs one, or drop it`). Still no questions, no notes file.

4. **Medium+ → check the plan against reality.** Read `references/tiers.md`,
   `references/standards/contribution.md`, and only the standards that match the reasons
   (auth → `security.md`, migrations/data → `data.md`, CI/infra → `release.md`). Then:
   - **The answers list.** ✗ = the plan doesn't say. ✓ = it mentions it — check that it
     actually answers it ("rollback: revert" doesn't undo a DROP).
   - **Impact from the code.** For each thing the plan changes (endpoint, function, column,
     event, config): find who uses it (grep callers, routes, queries, clients, jobs). Write
     what you found into the plan under **Affects** — this is the part people can't see
     from the plan alone.
   - **Impact from production** (when the policy has `usage:`): `bash scripts/targets.sh
     --plan .keel/plan.md`, add targets you found in the code, then `bash scripts/usage.sh
     "<target>" …`. Same rules as keel-check: exit 1 → skip; exit 3 → ask once to trust;
     `signal:` → at least high. Numbers go into **Affects** ("12k calls/7d, 18% from app
     2.3, which can't be updated server-side") and into the notes they change.
   - **Contradictions.** Steps that conflict with the code (the column is still read in
     3 places), with each other, or with the policy (freeze window, sensitive path).

5. **Write notes** to `.keel/plan-notes.txt`, each pinned to a verbatim phrase of the plan:

   ```
   === on drops the legacy_notes column
   Nothing backs up the notes or says how to undo this; src/admin/export.ts:12 still reads them.
   === general
   Who can call the new endpoint? Club admins only, or any logged-in user?
   ```

   The phrase after `=== on` must be copied from the plan as rendered (no backticks, no `**`).
   Severity is in the words, not labels: **must** (as written it causes data loss, a
   security hole, an outage or a broken client), **should** (a real gap with lower odds),
   **question** (only the user knows). No nits, no style, no rewrites of their wording.
   Medium: ≤ 3 notes. High/critical: ≤ 8. One note per root cause.

6. **Show it.**
   - **Plannotator** (when `review.ui: plannotator` is set in the policy or the voice
     profile, the user asks to see it, or the plan is high/critical and `plannotator` is
     installed): `bash scripts/plan_ui.sh open .keel/plan.md .keel/plan-notes.txt`, give the
     `url:` in one line, then `bash scripts/plan_ui.sh wait .keel/plan-ui/result.json`
     (exit 4 = still open; wait again). Exit 3 from `open` = not installed → terminal.
   - **Terminal** otherwise, in the output format below.

7. **Apply the answer.**
   - `annotated` → the `feedback` is the user's: the keel notes they kept (they agree) and
     their own. Update `.keel/plan.md` accordingly — re-read it first, the user may have
     edited it in the UI. Re-run step 2; check only what changed. If it's still high/critical
     and something new came up, show it once more; otherwise continue.
   - `approved` → the plan stands. Notes that rode along ("Approve with notes") are
     guidance to follow while building, not blockers.
   - `dismissed` → stop; don't build.
   - Terminal → the user's reply is the same thing.

8. **Seal it** — only once the user approved (Approve, or a yes in the terminal; a low tier
   needs no approval). Add a header to `.keel/plan.md`:
   `<!-- keel-plan · tier: high · approved: 2026-10-16 -->`. keel-check compares the diff
   with this plan later (planned steps not done, promised tests or rollback missing).
   If the user asked to build, build it now, following the plan.

## Output format (terminal)

Use the user's language. Keep it this short.

```
keel plan · HIGH — new endpoint, drops a column on bookings
must
  1. "drops the legacy_notes column" — no backup or undo, and src/admin/export.ts:12 still reads it
should
  2. "returns 200" — that test passes with or without the change; test that B can't delete A's bookings
questions
  3. who can call DELETE /bookings/old — club admins only?
added from the code and production
  · usage: 4,210 bookings have legacy_notes (of 9,800) — the DROP loses them
  · legacy_notes read in 3 places: src/api/bookings.js:41, src/admin/export.ts:12, api response (mobile app)
next: answer 3 and I'll update the plan · or open it in Plannotator
```

Omit empty sections. Low: one line.

## Never

- Plan a low-risk change in depth, or ask questions on a low tier.
- Ask the user something the code answers.
- Start building a high/critical plan with an open "must" — unless the user explicitly
  decides to, which is recorded as a waiver (`.agents/keel-waivers.md`, as in keel-check).
- Rewrite the user's plan into your own style; change only what the answers require.
- Run migrations, deploys or anything irreversible while planning.
