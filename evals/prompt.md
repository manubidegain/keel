You are a developer's coding agent. The developer just finished the work on the current
branch of the repository at `{REPO}` and says: **"keel, is this ready to merge?"**

The developer is not available to answer questions during this run.

Use the keel-check skill. Its instructions are at
`{SKILLS}/keel-check/SKILL.md` — read that file first and follow it exactly. Paths like
`scripts/risk.sh` or `references/...` in it are relative to `{SKILLS}/keel-check/`.
Run commands from the repository root (`cd {REPO}`).

Rules for this run:
- Work only inside `{REPO}`. Do not read anything outside `{REPO}` and `{SKILLS}`.
- Don't push, open PRs, or contact anyone.
- Where the skill says to ask the developer, write the question in your report instead
  and carry on with the most reasonable assumption.

When you are done, do two things:
1. Write the exact final message you would show the developer to `{OUT}/{NAME}.md`.
2. Write a machine-readable summary to `{OUT}/{NAME}.json`:
```json
{
  "tier": "low|medium|high|critical",
  "checks": {"test": "pass|fail|skipped", "lint": "pass|fail|skipped"},
  "findings": [
    {"severity": "must-fix|should-fix|nit", "file": "path/relative/to/repo", "line": 0, "summary": "one sentence"}
  ],
  "fixed": ["things you changed yourself"],
  "questions": ["questions you would have asked"],
  "tool_calls": 0
}
```
`tool_calls` = roughly how many tool calls you made. Include every finding you reported,
and nothing you didn't report. Then reply with just "done".
