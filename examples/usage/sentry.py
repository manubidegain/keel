#!/usr/bin/env python3
"""keel usage source: Sentry. Errors (and sampled requests, if tracing is on) for a route
in the last 7 days. Stdlib only.

  usage:
    sources:
      errors: "python3 .agents/usage/sentry.py"

Env: SENTRY_ORG, SENTRY_AUTH_TOKEN (scope: event:read / org:read). Optional: SENTRY_HOST
(default https://sentry.io), SENTRY_PROJECT (numeric id), SENTRY_DAYS (default 7).
Matches the route as Sentry names transactions ("GET /api/bookings/:id"); keep the method.
"""
import json, os, sys, urllib.parse, urllib.request

if os.environ.get("KEEL_TARGET_KIND") != "route":
    sys.exit(0)
for var in ("SENTRY_ORG", "SENTRY_AUTH_TOKEN"):
    if not os.environ.get(var):
        sys.exit(f"{var} not set")
host = os.environ.get("SENTRY_HOST", "https://sentry.io").rstrip("/")
days = int(os.environ.get("SENTRY_DAYS", "7"))
target = os.environ["KEEL_TARGET"].replace('"', '\\"')

def count(dataset, extra):
    params = [("field", "count()"), ("field", "count_unique(user)"), ("statsPeriod", f"{days}d"),
              ("dataset", dataset), ("query", f'transaction:"{target}" {extra}'.strip())]
    if os.environ.get("SENTRY_PROJECT"):
        params.append(("project", os.environ["SENTRY_PROJECT"]))
    url = f"{host}/api/0/organizations/{os.environ['SENTRY_ORG']}/events/?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {os.environ['SENTRY_AUTH_TOKEN']}"})
    with urllib.request.urlopen(req, timeout=15) as r:
        rows = json.load(r).get("data", [])
    row = rows[0] if rows else {}
    return int(row.get("count()", 0)), int(row.get("count_unique(user)", 0))

errors, affected = count("errors", "")
print(json.dumps({"metric": f"errors_{days}d", "value": errors, "label": f"errors/{days}d",
                  "detail": f"{affected} users affected" if errors else ""}))
try:
    sampled, _ = count("transactions", "")
    if sampled:
        print(json.dumps({"metric": f"sampled_requests_{days}d", "value": sampled, "label": f"traced requests/{days}d (sampled)"}))
except Exception:
    pass  # tracing not enabled: errors are still useful
