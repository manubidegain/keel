#!/usr/bin/env python3
"""keel usage source: PostHog. How many calls and people hit a route in the last 7 days,
and which app versions they use. Stdlib only.

  usage:
    sources:
      traffic: "python3 .agents/usage/posthog.py"

Env: POSTHOG_HOST (default https://us.posthog.com), POSTHOG_PROJECT_ID, POSTHOG_API_KEY
(personal API key with query read access). Optional: POSTHOG_EVENT (default $pageview; use
your API-request event if the backend captures one), POSTHOG_PATH_PROPERTY (default
$pathname), POSTHOG_VERSION_PROPERTY (default $app_version), POSTHOG_DAYS (default 7).
Handles route targets ("GET /api/bookings/:id"); prints nothing for anything else.
"""
import json, os, re, sys, urllib.request

kind = os.environ.get("KEEL_TARGET_KIND", "")
target = os.environ.get("KEEL_TARGET", "")
if kind != "route":
    sys.exit(0)
for var in ("POSTHOG_PROJECT_ID", "POSTHOG_API_KEY"):
    if not os.environ.get(var):
        sys.exit(f"{var} not set")
host = os.environ.get("POSTHOG_HOST", "https://us.posthog.com").rstrip("/")
event = os.environ.get("POSTHOG_EVENT", "$pageview")
prop = os.environ.get("POSTHOG_PATH_PROPERTY", "$pathname")
vprop = os.environ.get("POSTHOG_VERSION_PROPERTY", "$app_version")
days = int(os.environ.get("POSTHOG_DAYS", "7"))

path = target.split(" ", 1)[-1]                       # drop the method
like = re.sub(r":[A-Za-z0-9_]+|\{[^}]+\}|\[[^\]]+\]", "%", path)   # params → wildcard
def lit(s):  # HogQL string literal
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"
where = f"event = {lit(event)} AND properties[{lit(prop)}] LIKE {lit(like)} AND timestamp > now() - INTERVAL {days} DAY"

def query(q):
    req = urllib.request.Request(
        f"{host}/api/projects/{os.environ['POSTHOG_PROJECT_ID']}/query/",
        data=json.dumps({"query": {"kind": "HogQLQuery", "query": q}}).encode(),
        headers={"Authorization": f"Bearer {os.environ['POSTHOG_API_KEY']}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r).get("results", [])

calls, users = (query(f"SELECT count(), count(DISTINCT person_id) FROM events WHERE {where}") or [[0, 0]])[0]
versions = query(f"SELECT properties[{lit(vprop)}] AS v, count() AS c FROM events WHERE {where} GROUP BY v ORDER BY c DESC LIMIT 3")
detail = ", ".join(f"{v or 'unknown'} {round(100 * c / calls)}%" for v, c in versions) if calls else ""
print(json.dumps({"metric": f"calls_{days}d", "value": calls, "label": f"calls/{days}d", "detail": detail}))
print(json.dumps({"metric": f"users_{days}d", "value": users, "label": f"people/{days}d"}))
