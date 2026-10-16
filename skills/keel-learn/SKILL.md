---
name: keel-learn
description: Turn an incident or an escaped bug into a project rule so keel catches it next time. Finds the commit/PR that most likely caused it (stack trace → blame, symbols and error text → git pickaxe), explains why it got through (tier too low, missing rule, missed in review, no test), and proposes the smallest fix to the project's own standards — a sensitive path, one written rule with the incident as its reason, a regression test — plus a replayable case that keeps it caught. Use when the user says "X broke in production", "this bug got through", "postmortem", "incident", "why didn't keel catch this", "add a rule so this doesn't happen again", or pastes a stack trace or error from production — even if they don't name keel.
---

# keel-learn

Every incident is a rule the team didn't have yet. This skill writes it down where keel will
use it — `.agents/keel.yaml`, `.agents/standards/`, a test — and proves keel now catches the
change that caused it. Blameless: it's about the system, never the person.

## Steps

1. **What broke.** From the user: what happened, when it started, and any error, stack
   trace, Sentry/log link or affected endpoint. If there's a stack trace, take the frames in
   this repo (`path:line`), the function names, and the error message. Ask at most one
   question, only if there's nothing to search with.

2. **Find the cause.**
   `bash scripts/find_culprit.sh --file <path:line>… --symbol <fn>… --text "<error>" --since <~2 weeks before it started>`
   ranks candidate commits and shows what tier keel would have given each. Read the top
   diffs (`git show <sha>`) and confirm which one actually causes the behavior — reasoning
   from the code, and if it's cheap, a quick test that fails on that commit. If the commit
   names a PR and `gh` works, read its review (`gh pr view <n> --comments`) to see whether
   anyone raised it. If no commit explains it (config, data, infra, a third party), say so —
   step 4 then covers the process, not the code.

3. **Why it got through** — one line, the first that applies:
   - **tier too low** — keel would have said low/medium for a change that needed high;
   - **no rule** — the tier was right but no standard covers this mistake;
   - **rule missed** — a standard covers it and the review didn't apply it;
   - **no test** — nothing exercised the behavior (no existing test fails on the culprit);
   - **outside the code** — config, data, infra or a dependency.

4. **Propose the smallest change that would have caught it** — one or two of:
   - **Sensitive path** (tier too low): a glob under `sensitive:` in `.agents/keel.yaml`
     narrow enough not to flag unrelated work.
   - **One rule** (no rule / rule missed): append to `.agents/standards/<area>.md` (create
     it and list it under `standards:` if new), in keel's format —
     `- **<rule as an instruction>.** <how to check it>. (must-fix|should-fix)` followed by
     `  Why: <date> — <what happened, one line, no names>`. A rule that only restates a keel
     base standard isn't new: say the review missed it instead.
   - **Regression test**: the behavior that broke, failing on the culprit and passing on the
     fix — offer `keel-tests` for it.
   - **The case** (always, when there's a culprit commit): `.agents/keel-cases/<date>-<slug>/`
     with `change.diff` (`git show --format= <sha> -- <relevant files>`) and `case.md`
     (`expect: <tier it should get>`, what happened in two lines, the fix). These replay with
     `bash scripts/replay.sh` and keep the incident caught when the policy changes later.

   Show the proposal before writing anything: these files are the team's policy and get
   committed. Write them only after the user agrees.

5. **Prove it.** After writing: `bash scripts/replay.sh` must show the new case `ok` at the
   expected tier. For a new rule, re-read the culprit diff with the rule in hand and state
   the finding keel would now report, with its severity.

## Output

```
keel learn · double refunds since Oct 8
cause: 4e1c2a9 "simplify refund" (#12) — removed the already-cancelled check in src/payments/refund.js
why it got through: no rule — keel said HIGH, but nothing says refunds must be idempotent per booking
proposed
  · .agents/standards/payments.md: "Refunds and credits are idempotent per booking…"  (must-fix)
    Why: 2026-10-15 — cancelling twice credited the account twice
  · test: second cancel of the same booking is rejected (fails on 4e1c2a9) — keel-tests?
  · case .agents/keel-cases/2026-10-15-double-refund (expect: high)
next: write these? (nothing is changed until you say so)
```

Use the user's language. After writing: one line per file and the replay result.

## Never

- Name or blame the author; reference commits and PRs only.
- Add a broad rule ("be careful with payments") or a glob that makes everything high —
  that's noise, and noise is how keel gets ignored.
- Write to the policy or standards without the user's yes.
- Claim a cause you didn't confirm in the code; say "most likely" and why when unsure.
