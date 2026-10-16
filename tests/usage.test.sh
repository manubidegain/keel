#!/usr/bin/env bash
# Tests for shared/usage.sh and shared/targets.sh.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
U="$here/shared/usage.sh"; T="$here/shared/targets.sh"
pass=0; fail=0
dir="$(mktemp -d 2>/dev/null || mktemp -d -t keeltest)"; cd "$dir" || exit 1
export KEEL_CONFIG_DIR="$dir/config"
ok()   { pass=$((pass+1)); echo "ok   $1"; }
bad()  { fail=$((fail+1)); echo "FAIL $1"; printf '%s\n' "$2" | sed 's/^/     /'; }
has()  { printf '%s\n' "$2" | grep -Eq -- "$3" && ok "$1" || bad "$1" "$2"; }
hasnt(){ printf '%s\n' "$2" | grep -Eq -- "$3" && bad "$1" "$2" || ok "$1"; }

git init -q -b main; git config user.email t@t; git config user.name t
mkdir -p .agents/usage src migrations
cat > .agents/usage/traffic.sh <<'S'
#!/usr/bin/env bash
# fake provider: knows two routes
case "$KEEL_TARGET_KIND:$KEEL_TARGET" in
  "route:GET /api/bookings/:id") echo '{"metric":"calls_7d","value":12000,"label":"calls/7d","detail":"app 2.3 = 18%"}'
                                 echo '{"metric":"users_7d","value":340,"label":"users/7d"}' ;;
  "route:GET /api/legacy") echo '{"metric":"calls_7d","value":0,"label":"calls/7d"}' ;;
esac
S
cat > .agents/usage/data.sh <<'S'
#!/usr/bin/env bash
[ "$KEEL_TARGET_KIND" = column ] && echo "{\"metric\":\"rows_with_value\",\"value\":4210,\"label\":\"rows with a value in $1\"}"
echo "noise that is not json"
S
printf '#!/usr/bin/env bash\nsleep 5\n' > .agents/usage/slow.sh
cat > .agents/keel.yaml <<'Y'
project:
  users: 5000
usage:
  sources:
    traffic: "bash .agents/usage/traffic.sh"   # PostHog in real life
    data: "bash .agents/usage/data.sh {target}"
    slow: "bash .agents/usage/slow.sh"
  high_when:
    calls_7d: 1000
  timeout: 1
review:
  confirm: auto
Y
echo 'export const x = 1' > src/a.js; git add -A; git commit -qm init

out=$(bash "$U" "route:GET /api/bookings/:id"); code=$?
[ $code -eq 3 ] && ok "untrusted commands don't run (exit 3)" || bad "untrusted commands don't run (exit 3)" "exit $code: $out"
has "untrusted lists the commands" "$out" "traffic +bash .agents/usage/traffic.sh"
bash "$U" --trust >/dev/null
out=$(bash "$U" "route:GET /api/bookings/:id" "column:bookings.legacy_notes" "route:GET /api/legacy" "route:GET /nothing")
has "metrics with labels and detail" "$out" "calls/7d 12000 \(app 2.3 = 18%\) · users/7d 340"
has "{target} is passed safely" "$out" "rows with a value in bookings.legacy_notes 4210"
has "threshold → high signal" "$out" "^signal: 2:usage: route:GET /api/bookings/:id — calls_7d 12000 ≥ 1000"
has "zero traffic is called out" "$out" "^note: route:GET /api/legacy — calls_7d is 0"
has "no data is said plainly" "$out" "GET /nothing"
has "timeouts don't block" "$out" "slow +\(failed: timed out after 1s\)"
hasnt "non-JSON output is ignored" "$out" "noise"
# changed commands need trust again
sed -i.bak 's#traffic.sh"#traffic.sh --v2"#' .agents/keel.yaml
bash "$U" "route:GET /api/x" >/dev/null; code=$?
[ $code -eq 3 ] && ok "changed commands need trust again" || bad "changed commands need trust again" "exit $code"
bash "$U" --trust >/dev/null; echo '# edited' >> .agents/usage/data.sh
bash "$U" "route:GET /api/x" >/dev/null; code=$?
[ $code -eq 3 ] && ok "an edited usage script needs trust again" || bad "an edited usage script needs trust again" "exit $code"
KEEL_USAGE_TRUST=1 bash "$U" "route:GET /api/x" >/dev/null; code=$?
[ $code -eq 0 ] && ok "KEEL_USAGE_TRUST=1 (CI)" || bad "KEEL_USAGE_TRUST=1 (CI)" "exit $code"
printf 'project:\n  users: 1\n' > .agents/keel.yaml
bash "$U" "route:GET /x" >/dev/null; [ $? -eq 1 ] && ok "no usage block → exit 1" || bad "no usage block → exit 1" ""

# targets.sh
git add -A; git commit -qm p
cat > src/routes.js <<'S'
router.get('/api/bookings/:id', show)
app.post("/api/bookings", create)
export async function cancelBooking(id) {}
S
mkdir -p app/api/clubs/\[id\]; echo 'export async function GET() {}' > "app/api/clubs/[id]/route.ts"
echo 'ALTER TABLE bookings DROP COLUMN legacy_notes;' > migrations/003.sql
out=$(bash "$T")
has "express routes" "$out" "^route:GET /api/bookings/:id$"
has "post route" "$out" "^route:POST /api/bookings$"
has "next.js app route" "$out" "^route:/api/clubs/:id$"
has "dropped column" "$out" "^column:bookings.legacy_notes$"
has "exported function" "$out" "^symbol:cancelBooking$"
printf '1. Drop the `legacy_notes` column from `bookings`.\n2. Change `GET /api/bookings/:id` to return cents.\n' > plan.md
out=$(bash "$T" --plan plan.md)
has "plan: column in prose" "$out" "^column:bookings.legacy_notes$"
has "plan: route in prose" "$out" "^route:GET /api/bookings/:id$"

rm -rf "$dir"
echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
