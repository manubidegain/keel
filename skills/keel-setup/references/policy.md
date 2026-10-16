# keel policy file — `.agents/keel.yaml`

Every field is optional. A missing file means "use defaults detected from the repo".
Keep the file short: only write what differs from the defaults or what can't be detected.

```yaml
# Optional: inherit an organization's standards (a git URL or a local path).
# The org file has the same shape; anything set here overrides it.
extends: github.com/acme/engineering-standards/keel.yaml

project:
  type: web-app            # web-app | mobile | api | library | cli | internal | data
  data: [personal, payments]   # none | personal | payments | financial | health | minors | credentials
  users: 5000              # rough order of magnitude of real users (0 = not live yet)
  rollback: "git revert + redeploy, ~5 min"   # how a bad release is undone, in one line
  deploy: vercel           # free text: vercel, fly, k8s, app-store, manual...
  owners: ["@manu"]        # who accepts risk on high/critical changes

commands:                  # how checks are run here; `none` disables a check
  test: npm test
  lint: npm run lint
  typecheck: npx tsc --noEmit
  build: npm run build
  e2e: npx playwright test

sensitive:                 # extra globs that make a change HIGH risk (added to built-in rules)
  - "src/billing/**"
  - "app/api/webhooks/**"

relaxed:                   # globs keel should treat as LOW even if a rule matches (generated code, fixtures)
  - "src/generated/**"

tiers:                     # override what each tier requires (defaults in keel-check/references/tiers.md)
  medium:
    require: [test, lint, typecheck]
  high:
    require: [test, lint, typecheck, build, e2e]
    review_until: no_must_fix_no_should_fix

usage:                     # optional: production numbers for what a change touches (see below)
  sources:                 # name: command printing JSON lines; runs per target, read-only
    traffic: "python3 .agents/usage/posthog.py"
    data: "bash .agents/usage/postgres.sh"
  high_when:               # a metric at or above this → the change counts as high risk
    calls_7d: 1000
    rows_with_value: 1
  timeout: 20              # seconds per command
  cache_minutes: 60

hooks:                     # how strict the optional hooks are (installed per person by keel-setup)
  stop: suggest            # off | suggest (one-line note to you) | ask (the agent runs keel-check, once)
  pre_push: high           # off | high | critical — stop pushes at or above this tier until checked

freeze:                    # windows where high/critical changes need explicit owner approval
  - "Fri 16:00-Mon 08:00"

standards:                 # extra standard files (project or org), read in addition to keel's base
  - .agents/standards/api.md

review:
  confirm: auto            # always | auto | never — when to ask before posting (see keel-review)
  language: auto           # language for PR comments; auto = the PR's language
  max_comments: 15         # cap inline comments per review; the rest go in the summary
  nits: false              # post nits at all?
  signature: ""            # appended to review summaries only if set, e.g. "— Manu"
  ui: terminal             # terminal | plannotator — where to show reviews and plans
```

## Field notes

- **data** raises the floor: in projects that handle personal/payment/health data, side
  effects (jobs, webhooks, emails) and dependency changes count as high risk.
- **users: 0** means not in production yet: keel relaxes release requirements but not
  security ones.
- **rollback** is the most important line in the file. If nobody can write it, that is
  itself a finding for high-risk changes.
- **relaxed** exists to keep false positives down. Use it the moment keel flags generated
  or vendored code.
- **review.confirm: auto** asks before approving/requesting changes, security findings on
  public repos, critical PRs, outside contributors and big reviews; posts the rest directly.
- **review.ui: plannotator** opens the drafted review on the diff in
  [Plannotator](https://plannotator.ai) whenever keel would ask first: edit, delete or add
  comments, then "Send Feedback" posts exactly that. keel-plan uses it too: notes pinned to
  the plan's text, Approve or Send Feedback (it opens high/critical plans there whenever
  Plannotator is installed). With `confirm: always` every review goes
  through it. Falls back to the terminal if Plannotator isn't installed. It's a personal
  preference, so it can also go in `~/.config/keel/voice.md` as `ui: plannotator`.
- **usage** turns "this endpoint is probably used" into "12,000 calls last week, 18% from
  app 2.3". keel finds the targets (routes, tables, columns, functions) in the plan or
  diff, runs each source with `KEEL_TARGET` / `KEEL_TARGET_KIND` set, and reads lines like
  `{"metric":"calls_7d","value":12000,"label":"calls/7d","detail":"app 2.3 = 18%"}`.
  Templates for PostHog, Sentry, Postgres/Supabase and access logs are in
  `references/usage-sources/`. The commands are code from the repo, so each person trusts
  them once (and again whenever they change); `KEEL_USAGE_TRUST=1` in CI. Credentials go in
  env vars, never here.
- **hooks** only take effect for people who installed them (`install_hooks.sh`). A change
  counts as checked when keel-check ran on exactly that content, committed or not.
- The voice profile is personal and lives outside the repo: `~/.config/keel/voice.md`.
- Unknown keys are ignored, so teams can add their own.
