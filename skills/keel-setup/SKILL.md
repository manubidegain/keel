---
name: keel-setup
description: Set up keel in a repository — detects the stack, test/lint/build commands, sensitive areas and deploy method, asks only what it cannot detect, writes the project policy file `.agents/keel.yaml`, and optionally makes keel run on its own (git pre-push + Claude Code hook) and connects production usage data. Use when the user says "set up keel", "configure keel", "keel init", "define our standards/rules for this project", "make keel run automatically", "install keel hooks", "connect usage data / analytics to keel", or when another keel skill finds no policy file and the user wants one. Also use to update an existing keel policy.
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
   - Run keel on its own? (stop unchecked risky pushes + a nudge when the agent finishes a
     risky change — see step 6). Default yes.
   Ask "anything else that should always be treated as high risk?" only instead of a
   question detection already answered.
   If the user is not there to answer, write your best guess and mark those lines `# guess`.

4. **Write the file.** Read `references/policy.md` for the schema. Write only fields that
   differ from defaults or that you learned; keep it short and commented. If a policy exists,
   update it in place and keep the user's keys and comments.

5. **Housekeeping.**
   - Add `.keel/` to `.gitignore` (local logs and drafts).
   - Offer — do not force — one line in AGENTS.md (or CLAUDE.md if that is what the repo uses):
     `This project uses keel: run the keel-check skill before committing; policy in .agents/keel.yaml.`

6. **Hooks (if they said yes).** `bash scripts/install_hooks.sh --all`. Personal to this
   clone: nothing is committed. It installs a git `pre-push` that stops HIGH/CRITICAL pushes
   whose exact content keel-check hasn't seen (bypass: `git push --no-verify`), and a Claude
   Code Stop hook in `.claude/settings.local.json` that says so in one line when the agent
   finishes such a change. If they already use husky/lefthook, it prints the one line to add
   instead of touching their hooks — show it. How strict the hooks are is set for the whole
   team with `hooks:` in the policy (`references/policy.md`). Users of the Claude Code
   plugin already get the Stop hook. `--status` / `--uninstall` when asked.

7. **Usage data (offer once, never required).** If the project is live and uses PostHog,
   Sentry, Postgres/Supabase or has access logs (look at dependencies and env examples),
   offer to connect them: copy the matching templates from `references/usage-sources/`
   (or write one from the contract in its README) to `.agents/usage/`, add `usage:` to the policy, and tell the user which env vars to set.
   Read-only credentials only, never in the policy file. Then
   `bash scripts/usage.sh --list` to show what's configured.

8. **Verify.** Run `bash scripts/run.sh test lint` once so the user sees the commands work.
   If a command fails because it is wrong (not because tests fail), fix it in the policy.

## Output

Show the final policy file and one line per decision you guessed. Nothing else.

## Rules

- Never invent commands: if a check has no command, leave it out or set `none`.
- Never put secrets, tokens or real user data in the policy file. It is committed.
- Prefer detection over questions. Every question has to earn its place.
