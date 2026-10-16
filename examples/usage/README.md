# Usage sources

Templates for `usage:` in `.agents/keel.yaml`. Copy the ones you use to `.agents/usage/`,
set their env vars, and keel shows real numbers next to the risk of each change:

```
usage:
  route:GET /api/bookings/:id
    traffic   calls/7d 12000 (app 2.3 41%, app 2.4 59%) · people/7d 340
    errors    errors/7d 3 (2 users affected)
  column:bookings.legacy_notes
    data      rows with a value 4210 (of 9800 rows)
```

| File | What it answers | Needs |
|---|---|---|
| `posthog.py` | calls, people and app versions per route | `POSTHOG_PROJECT_ID`, `POSTHOG_API_KEY` |
| `sentry.py` | errors (and traced requests) per route | `SENTRY_ORG`, `SENTRY_AUTH_TOKEN` |
| `postgres.sh` | rows a table/column change touches (Supabase too) | `KEEL_DATABASE_URL` (read-only), `psql` |
| `logs.sh` | calls, clients and user agents from access logs | log file paths |

```yaml
usage:
  sources:
    traffic: "python3 .agents/usage/posthog.py"
    errors: "python3 .agents/usage/sentry.py"
    data: "bash .agents/usage/postgres.sh"
  high_when:            # any of these → the change is treated as high risk
    calls_7d: 1000
    users_7d: 50
    rows_with_value: 1
  timeout: 20           # seconds per command
  cache_minutes: 60
```

**Write your own** in any language: keel runs the command with `KEEL_TARGET`
(`GET /api/x`, `bookings.notes`, `priceFor`) and `KEEL_TARGET_KIND`
(`route` · `table` · `column` · `symbol`) set, and reads one JSON object per line:

```json
{"metric": "calls_7d", "value": 12000, "label": "calls/7d", "detail": "app 2.3 = 41%"}
```

Print nothing when you have no data for that target. Use read-only credentials: keel only
reads. The commands run only after you trust them once per repo (keel asks), and again if
they change — a PR can't sneak in a new one.
