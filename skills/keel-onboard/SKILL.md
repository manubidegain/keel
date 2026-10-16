---
name: keel-onboard
description: Explain how a project works and how work gets done in it — how to run it, test it and deploy it, which areas are risky, and which standards apply — in one short briefing. Use when someone is new to a repo or asks "how does this project work?", "how do we work here?", "what should I know before touching this?", "how do I run/test/deploy this?", or "what are the rules in this repo?".
---

# keel-onboard

One-page briefing for someone about to work in this repository. Read-only: never changes
files, never runs the app.

## Steps

1. Run `bash scripts/detect.sh .` (relative to this skill's folder) for stack and commands.
2. Read, if present: `.agents/keel.yaml`, README, AGENTS.md / CLAUDE.md, CONTRIBUTING,
   `.agents/keel-waivers.md`, and the standards files listed in the policy. Skim the
   top-level folder layout.
3. Look at the last ~30 commits (`git log --oneline -30`) to see what's active and how
   commits/PRs are written here.
4. Write the briefing in the user's language, at most ~40 lines:

```
<project> · <one line: what it is, stack>
run       <command to install + start locally>
check     <test / lint / typecheck commands>
ship      <how it deploys, how a bad release is undone>
careful   <sensitive areas and why — from the policy and built-in rules>
rules     <the 3–6 standards that matter most here, one line each>
open      <active waivers or known debts, if any>
start     <one good first area to read, with a file path>
```

If something important is unknown (no rollback, no test command, no README), say so in one
line under `gaps` — that is useful information for a newcomer and for the team.
