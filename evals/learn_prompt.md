You are a developer's coding agent, working in the repository at `{REPO}`. The developer
says: **"{INCIDENT}"**

The developer is not available to answer questions during this run.

Use the keel-learn skill. Its instructions are at `{SKILLS}/keel-learn/SKILL.md` — read that
file first and follow it exactly. Paths like `scripts/find_culprit.sh` in it are relative to
`{SKILLS}/keel-learn/`. Run commands from the repository root (`cd {REPO}`).

Rules for this run:
- Work only inside `{REPO}`. Do not read anything outside `{REPO}` and `{SKILLS}`.
- Don't push, open PRs, or contact anyone. The developer can't approve anything during this run.

When you are done, do two things:
1. Write the exact final message you would show the developer to `{OUT}/{NAME}.md`.
2. Write a machine-readable summary to `{OUT}/{NAME}.json`:
```json
{
  "culprit": {"sha": "short sha", "subject": "commit subject"},
  "why": "tier too low | no rule | rule missed | no test | outside the code",
  "proposals": [{"kind": "sensitive|rule|test|case", "file": "path it would go to", "text": "one line"}],
  "files_written": ["paths you created or changed in the repo, if any"],
  "tool_calls": 0
}
```
Then reply with just "done".
