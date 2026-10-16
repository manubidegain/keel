---
name: keel-setup
description: Set up keel in a repository — detects the stack, test/lint/build commands, sensitive areas and deploy method, asks only what it cannot detect, and writes the project policy file `.agents/keel.yaml`. Use when the user says "set up keel", "configure keel", "keel init", "define our standards/rules for this project", or when another keel skill finds no policy file and the user wants one. Also use to update an existing keel policy.
---

# keel-setup

Create or update `.agents/keel.yaml`, the file that tells the other keel skills how this
project works and what is risky in it. Target: done in under two minutes, at most four
questions.

## Steps

1. **Detect.** Run `bash scripts/detect.sh .` (path relative to this skill's folder) from the
   repo root. It prints stack, commands, CI, deploy hints, migration folders and whether a
   policy already exists. It never executes project code.

2. **Look around briefly** (only what detection can't see, ~1 minute max):
   - README / AGENTS.md / CLAUDE.md / CONTRIBUTING.md for how the project is run and deployed.
   - Top-level folders, to spot domain-sensitive areas the built-in rules would miss
     (e.g. `src/ledger/`, `app/api/webhooks/`). Built-in rules already cover auth, payments,
     migrations, infra/CI, env/secrets, API contracts, jobs/webhooks and dependencies.
   - Generated or vendored code that should go under `relaxed:`.

3. **Ask only what is missing**, in one message, at most four questions, with the detected
   guess pre-filled so the user can just confirm:
   - What data does it handle? (none / personal / payments / health / minors…)
   - Roughly how many real users? (0 if not live)
   - How is a bad release undone, and how long does it take?
   - Anything else that should always be treated as high risk?
   If the user is not there to answer, write your best guess and mark those lines `# guess`.

4. **Write the file.** Read `references/policy.md` for the schema. Write only fields that
   differ from defaults or that you learned; keep it short and commented. If a policy exists,
   update it in place and keep the user's keys and comments.

5. **Housekeeping.**
   - Add `.keel/` to `.gitignore` (local logs and drafts).
   - Offer — do not force — one line in AGENTS.md (or CLAUDE.md if that is what the repo uses):
     `This project uses keel: run the keel-check skill before committing; policy in .agents/keel.yaml.`

6. **Verify.** Run `bash scripts/run.sh test lint` once so the user sees the commands work.
   If a command fails because it is wrong (not because tests fail), fix it in the policy.

## Output

Show the final policy file and one line per decision you guessed. Nothing else.

## Rules

- Never invent commands: if a check has no command, leave it out or set `none`.
- Never put secrets, tokens or real user data in the policy file. It is committed.
- Prefer detection over questions. Every question has to earn its place.
