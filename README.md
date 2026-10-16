# keel

**Risk-aware checks and code review for any project, as agent skills.**

keel is the senior teammate who looks at your change before it ships: it takes a second on
a typo fix and gets thorough when you touch auth, payments or a migration. It fixes the
easy stuff itself, asks only what needs judgment, and leaves your PR description ready.
It also reviews other people's pull requests and comments on them.

Works with any agent that supports [Agent Skills](https://agentskills.io): Claude Code,
Cursor, Codex, Gemini CLI, GitHub Copilot, VS Code and more. Works with any stack.

```
keel · HIGH — touches src/auth/session.ts, adds a migration
✓ test  ✓ lint  ✓ typecheck  ✗ build
must-fix
  1. session.ts:42 — refresh token never expires; a stolen token works forever
should-fix
  2. 004_add_index.sql — CREATE INDEX without CONCURRENTLY locks big tables
fixed for you
  · removed 2 unused imports · fixed build error (missing export in auth/index.ts)
next: fix #1 (want me to?) · PR description ready in .keel/pr.md
```

## Install

```bash
npx skills add manubidegain/keel
```

Claude Code plugin:

```
/plugin marketplace add manubidegain/keel
/plugin install keel@keel
```

Or copy `skills/*` into your agent's skills folder (`.agents/skills/`, `.claude/skills/`, …).

## Skills

| Skill | Say something like | What it does |
|---|---|---|
| **keel-check** | "keel", "is this ready?", "check before I commit" | Classifies the change's risk, runs only the checks that risk needs, reviews the diff, fixes the simple things, prepares the PR description |
| **keel-review** | "review PR 42", *pastes a PR link* | Reviews someone else's PR at the depth its risk calls for and posts it as you, in your voice — asking first only when it matters |
| **keel-tests** | "add tests for this", "what should we test?" | Writes few, valuable tests chosen by risk — each proven by breaking the code it protects and watching it fail |
| **keel-setup** | "set up keel" | Detects your stack and commands, asks ≤4 questions, writes `.agents/keel.yaml` |
| **keel-onboard** | "how does this project work?" | One-page briefing: run, test, ship, risky areas, rules that matter |

## How it decides how careful to be

A script (no AI, ~instant) reads the diff and assigns a tier:

| Tier | Triggered by | keel does |
|---|---|---|
| **low** | docs, copy, small code changes | tests + lint, quick look, done |
| **medium** | dependencies, jobs/webhooks/emails, big diffs, code without tests | + typecheck, review against standards |
| **high** | auth, permissions, payments, migrations, infra/CI, env, public APIs, your sensitive paths | + build + e2e, reads callers, iterates until no must-fix/should-fix |
| **critical** | irreversible data operations, possible secrets, high-risk during a freeze | + written rollback, owner sign-off |

Most changes are low and get a one-line answer. You only pay for depth when it matters.

## Configure (optional)

keel works with no config. To teach it about your project, run `keel-setup` or write
`.agents/keel.yaml`:

```yaml
project:
  data: [personal, payments]
  users: 5000
  rollback: "Vercel instant rollback, ~1 min"
sensitive:
  - "src/billing/**"
relaxed:
  - "src/generated/**"
```

Full schema: [`skills/keel-setup/references/policy.md`](skills/keel-setup/references/policy.md).
Examples: [`examples/`](examples/). Organizations can share one base policy with `extends:`.

## Standards

Opinionated defaults, each rule with its reason, all overridable per project:
[code](skills/keel-check/references/standards/code.md) ·
[security](skills/keel-check/references/standards/security.md) ·
[data & migrations](skills/keel-check/references/standards/data.md) ·
[testing](skills/keel-check/references/standards/testing.md) ·
[release & CI](skills/keel-check/references/standards/release.md)

## Your name, your voice

Reviews, comments and PRs are posted with **your** GitHub login and written the way you
write — no "AI review" footers, labels or markers. keel learns your style once from your own
past review comments (`keel-review` offers it the first time) and keeps the profile at
`~/.config/keel/voice.md`, outside every repo, editable by hand.

It asks before posting only when it matters: approving or requesting changes, security
findings on public repos, critical PRs, outside contributors, or long reviews
(`review.confirm: auto`, also `always` / `never`). Everything else is posted and linked.

If your agent adds its own attribution to commits or PRs, turn it off in the agent — in
Claude Code: `"attribution": {"commit": "", "pr": ""}` in `~/.claude/settings.json`.

## Automatic PR reviews

Copy [`examples/github-action.yml`](examples/github-action.yml) to
`.github/workflows/keel-review.yml` and add an `ANTHROPIC_API_KEY` secret, plus a
`KEEL_GH_TOKEN` of the reviewer so reviews appear under their name. keel reviews each PR
and posts one review as a comment (never approves or blocks on its own).

## Does it work?

Blind evals on planted bugs (auth bypass, IDOR, destructive migration, leaked secret,
unsigned webhook, a pricing off-by-one hidden in a "refactor", a units change that breaks a
caller, a prompt injection) plus clean changes to measure false alarms:

| Model | Planted problems found | False must-fix |
|---|---|---|
| Opus | 11/11 | 0 |
| Sonnet | 6/6 | 0 |
| Haiku | 6/6 | 0 |

keel-tests' tests killed 7/7 independent mutations. Details, limits and how to run them:
[`evals/`](evals/RESULTS.md).

## Proven, not plausible

Agents make code cheap; what's scarce is code that's **shown to work**. By default keel holds
every change to that bar ([`contribution.md`](skills/keel-check/references/standards/contribution.md)):

- **Tests must fail without your change.** `prove.sh` reverts the change in a throwaway
  worktree and runs the suite. If it still passes, the tests don't test the change.
- **No slop.** `slop.sh` flags what the change adds: `as any` / `as unknown as`,
  `@ts-ignore` and lint disables, leftover debug output, TODOs nobody owns, `.only` / `.skip`.
- **Ready means answered.** Have you seen it run? Do the types and names tell the truth?
  Did you test the edges? Could someone on call debug it at 3 AM? Any "not sure" → not ready.
- **Review until clean.** Two consecutive passes with nothing new, or four passes.
- **Evidence in the PR.** What was run, what it showed, and the revert check — so the
  reviewer doesn't have to prove it for you.

## Principles

- **Fast by default.** Detect before asking. Scripts for mechanics, reasoning only for review.
- **Useful, not bureaucratic.** It fixes and prepares things, not just reports them.
- **Few false alarms.** When unsure, the lower severity. Nits are off by default.
- **Tests with value.** Never tests for coverage's sake.
- **You stay in control.** Nothing is posted, merged or deleted without your yes. Skipping
  a rule is allowed — it's just written down.

## Contributing

Rules live in plain Markdown. Propose a new rule or standard with a PR that explains the
problem it prevents (a real incident is the best reason), ideally with an eval scenario
that shows it. Scripts are portable bash (macOS bash 3.2+): edit `shared/`, run
`scripts/sync.sh`, then `tests/risk.test.sh`.

MIT licensed.
