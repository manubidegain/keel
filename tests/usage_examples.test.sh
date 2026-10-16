#!/usr/bin/env bash
# Tests for the usage source templates in examples/usage (no real providers: a local stub
# server stands in for PostHog and Sentry; logs use a sample file).
set -u
ex="$(cd "$(dirname "$0")/.." && pwd)/examples/usage"
pass=0; fail=0
dir="$(mktemp -d 2>/dev/null || mktemp -d -t keeltest)"
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; printf '%s\n' "$2" | sed 's/^/     /'; }
has() { printf '%s\n' "$2" | grep -Eq -- "$3" && ok "$1" || bad "$1" "$2"; }

# ---- logs.sh
cat > "$dir/access.log" <<'L'
1.1.1.1 - - [16/Oct/2026:10:00:00 +0000] "GET /api/bookings/42 HTTP/1.1" 200 12 "-" "courtbook-ios/2.3 CFNetwork"
1.1.1.1 - - [16/Oct/2026:10:00:01 +0000] "GET /api/bookings/43?x=1 HTTP/1.1" 200 12 "-" "courtbook-ios/2.3 CFNetwork"
2.2.2.2 - - [16/Oct/2026:10:00:02 +0000] "GET /api/bookings/44 HTTP/1.1" 200 12 "-" "Mozilla/5.0 (Mac)"
3.3.3.3 - - [16/Oct/2026:10:00:03 +0000] "POST /api/bookings/44 HTTP/1.1" 200 12 "-" "Mozilla/5.0 (Mac)"
3.3.3.3 - - [16/Oct/2026:10:00:04 +0000] "GET /api/bookings/44/invoice HTTP/1.1" 200 12 "-" "Mozilla/5.0 (Mac)"
{"method":"GET","path":"/api/bookings/45","ip":"4.4.4.4","user_agent":"courtbook-android/2.4"}
L
out=$(KEEL_TARGET_KIND=route KEEL_TARGET="GET /api/bookings/:id" bash "$ex/logs.sh" "$dir/access.log")
has "logs: counts only the route and method (4 calls)" "$out" '"metric":"calls","value":4'
has "logs: distinct clients" "$out" '"metric":"clients","value":3'
has "logs: top user agents" "$out" 'courtbook-ios/2.3 50%'
out=$(KEEL_TARGET_KIND=column KEEL_TARGET="a.b" bash "$ex/logs.sh" "$dir/access.log")
[ -z "$out" ] && ok "logs: ignores non-route targets" || bad "logs: ignores non-route targets" "$out"

# ---- stub server for PostHog and Sentry
command -v python3 >/dev/null || { echo "skip: python3 not found"; echo "---"; echo "$pass passed, $fail failed"; exit 0; }
cat > "$dir/stub.py" <<'P'
import http.server, json, sys, urllib.parse
log = open(sys.argv[1], "a")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, obj):
        b = json.dumps(obj).encode(); self.send_response(200)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        q = body["query"]["query"]; log.write("POSTHOG " + self.headers.get("Authorization","") + " " + q + "\n"); log.flush()
        self.reply({"results": [["2.3", 300], ["2.4", 100]]} if "GROUP BY" in q else {"results": [[400, 25]]})
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); qs = urllib.parse.parse_qs(u.query)
        log.write("SENTRY " + qs["dataset"][0] + " " + qs["query"][0] + "\n"); log.flush()
        self.reply({"data": [{"count()": 7, "count_unique(user)": 3}]} if qs["dataset"][0] == "errors" else {"data": [{"count()": 90, "count_unique(user)": 0}]})
s = http.server.HTTPServer(("127.0.0.1", 0), H); print(s.server_address[1], flush=True); s.serve_forever()
P
python3 "$dir/stub.py" "$dir/req.log" > "$dir/port" & spid=$!
i=0; while [ ! -s "$dir/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
port=$(cat "$dir/port")

out=$(KEEL_TARGET_KIND=route KEEL_TARGET="GET /api/bookings/:id" POSTHOG_HOST="http://127.0.0.1:$port" \
      POSTHOG_PROJECT_ID=1 POSTHOG_API_KEY=phx_test python3 "$ex/posthog.py")
has "posthog: calls with version split" "$out" '"metric": "calls_7d", "value": 400, .*"detail": "2.3 75%, 2.4 25%"'
has "posthog: people" "$out" '"metric": "users_7d", "value": 25'
has "posthog: route params become LIKE wildcards" "$(cat "$dir/req.log")" "LIKE '/api/bookings/%'"
out=$(KEEL_TARGET_KIND=route KEEL_TARGET="GET /x' OR 1=1 --" POSTHOG_HOST="http://127.0.0.1:$port" \
      POSTHOG_PROJECT_ID=1 POSTHOG_API_KEY=k python3 "$ex/posthog.py")
has "posthog: quotes in the target are escaped" "$(cat "$dir/req.log")" "LIKE '/x\\\\' OR 1=1 --'"
out=$(KEEL_TARGET_KIND=route KEEL_TARGET="GET /api/bookings/:id" SENTRY_HOST="http://127.0.0.1:$port" \
      SENTRY_ORG=o SENTRY_AUTH_TOKEN=t python3 "$ex/sentry.py")
has "sentry: errors with users affected" "$out" '"metric": "errors_7d", "value": 7, .*"3 users affected"'
has "sentry: sampled requests" "$out" '"value": 90'
has "sentry: transaction name keeps the method" "$(cat "$dir/req.log")" 'SENTRY errors transaction:"GET /api/bookings/:id"'
out=$(KEEL_TARGET_KIND=column KEEL_TARGET=a.b python3 "$ex/sentry.py"); [ -z "$out" ] && ok "sentry: ignores non-route targets" || bad "sentry: ignores non-route targets" "$out"
kill $spid 2>/dev/null

rm -rf "$dir"
echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
