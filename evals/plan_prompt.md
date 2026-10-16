You are a developer's coding agent, working in the repository at `{REPO}`. The developer
says: **"{REQUEST}"** and has written this plan, saved at `{REPO}/.keel/plan.md`:

```
{PLAN}
```

The developer is not available to answer questions during this run.

Use the keel-plan skill. Its instructions are at `{SKILLS}/keel-plan/SKILL.md` — read that
file first and follow it exactly. Paths like `scripts/plan_risk.sh` or `references/...` in it
are relative to `{SKILLS}/keel-plan/`. Run commands from the repository root (`cd {REPO}`).

Rules for this run:
- Work only inside `{REPO}`. Do not read anything outside `{REPO}` and `{SKILLS}`.
- Do not build the change — this run is about the plan only. Do not open Plannotator.
- Where the skill says to ask the developer, put the question in your report and carry on.

When you are done, do two things:
1. Write the exact final message you would show the developer to `{OUT}/{NAME}.md`.
2. Write a machine-readable summary to `{OUT}/{NAME}.json`:
```json
{
  "tier": "low|medium|high|critical",
  "notes": [
    {"severity": "must|should|question", "quote": "phrase of the plan it is pinned to, or empty", "text": "the note"}
  ],
  "added_from_code": ["facts you found in the code and added to the plan"],
  "tool_calls": 0
}
```
Include every note you reported and nothing else. Then reply with just "done".
