#!/usr/bin/env bash
# keel · usage.sh — production numbers for the things a change touches, from commands the
# project declares under `usage:` in .agents/keel.yaml. keel never talks to a provider itself.
#
# Usage:
#   usage.sh <target>...          # targets from targets.sh, e.g. "route:GET /api/x" "column:bookings.notes"
#   usage.sh --trust              # the user agreed to run this repo's usage commands
#   usage.sh --list               # show the declared sources and whether they're trusted
#   --policy <file>  --fresh (ignore cache)
#
# Each source command runs once per target with KEEL_TARGET (e.g. "GET /api/x"),
# KEEL_TARGET_KIND (route|table|column|symbol) and KEEL_TARGET_FULL set; `{target}` in the
# command becomes "$KEEL_TARGET". It prints JSON lines, one per metric:
#   {"metric":"calls_7d","value":12000,"label":"calls, 7 days","detail":"app 2.3 = 18%"}
# Nothing printed = no data for that target. Failures and timeouts never stop keel.
#
# The commands come from the repo, so they're code: they run only after the user trusts them
# (once per repo, again whenever they or anything in .agents/usage/ change).
# KEEL_USAGE_TRUST=1 trusts them (CI).
# Exit: 0 ok · 1 no usage configured · 3 not trusted yet.
set -u
policy=".agents/keel.yaml"; fresh=0; mode=run; targets=()
while [ $# -gt 0 ]; do
  case "$1" in
    --policy) policy="$2"; shift 2 ;;
    --fresh) fresh=1; shift ;;
    --trust) mode=trust; shift ;;
    --list) mode=list; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) targets+=("$1"); shift ;;
  esac
done
[ -f "$policy" ] || { echo "no usage configured (no $policy)"; exit 1; }

# ---------------------------------------------------------------- read the usage: block
block="$(awk '/^usage:/{on=1;next} /^[^[:space:]#]/{on=0} on' "$policy")"
[ -n "$(printf '%s' "$block" | tr -d '[:space:]')" ] || { echo "no usage configured (add usage: to $policy)"; exit 1; }
sub_map() { # sub_map <key> → "name<TAB>value" lines from a nested map under usage:
  printf '%s\n' "$block" | awk -v k="$1" '
    $0 ~ "^[[:space:]]+" k ":[[:space:]]*$" { on=1; match($0,/^[[:space:]]*/); ind=RLENGTH; next }
    on { match($0,/^[[:space:]]*/); if (RLENGTH <= ind && $0 ~ /[^[:space:]]/) on=0 }
    on && /^[[:space:]]+[A-Za-z0-9_-]+:/ {
      line=$0; sub(/^[[:space:]]+/,"",line); name=line; sub(/:.*/,"",name); val=line; sub(/^[^:]*:[[:space:]]*/,"",val)
      sub(/[[:space:]]+#[^"'\'']*$/,"",val)
      if (val ~ /^".*"$/ || val ~ /^'\''.*'\''$/) val=substr(val,2,length(val)-2)
      print name "\t" val
    }'
}
sources="$(sub_map sources)"
thresholds="$(sub_map high_when)"
timeout=$(printf '%s\n' "$block" | awk '/^[[:space:]]+timeout:/{print $2; exit}'); timeout=${timeout:-20}
ttl=$(printf '%s\n' "$block" | awk '/^[[:space:]]+cache_minutes:/{print $2; exit}'); ttl=${ttl:-60}
[ -n "$sources" ] || { echo "no usage sources (usage.sources is empty)"; exit 1; }

# ---------------------------------------------------------------- trust (per repo, per exact commands)
sha() { if command -v shasum >/dev/null; then shasum -a 256 | cut -c1-16; else sha256sum | cut -c1-16; fi; }
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
# the scripts the commands run are part of what's trusted: any edit to .agents/usage/ asks again
scripts_sum=$(find "$root/.agents/usage" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do cat "$f"; done | sha)
fp=$(printf '%s\n%s\n%s\n' "$root" "$sources" "$scripts_sum" | sha)
store="${KEEL_CONFIG_DIR:-$HOME/.config/keel}/trusted-usage"
trusted() { [ "${KEEL_USAGE_TRUST:-0}" = 1 ] || grep -qx "$fp" "$store" 2>/dev/null; }

if [ "$mode" = trust ]; then
  mkdir -p "$(dirname "$store")"; trusted || echo "$fp" >> "$store"
  echo "trusted: usage commands of $root"; exit 0
fi
if [ "$mode" = list ] || ! trusted; then
  if trusted; then echo "usage sources (trusted):"; else echo "usage sources (NOT trusted yet — they run as code on this machine):"; fi
  printf '%s\n' "$sources" | awk -F'\t' '{printf "  %-10s %s\n", $1, $2}'
  if ! trusted; then
    echo "ask the user once; if they agree: bash $0 --trust"
    exit 3
  fi
  exit 0
fi
[ ${#targets[@]} -gt 0 ] || { echo "no targets (try: bash targets.sh)"; exit 0; }

# ---------------------------------------------------------------- run
cache="$root/.keel/usage"; mkdir -p "$cache"
run_one() { # run_one <name> <cmd> <kind> <value> <full> → JSON lines on stdout, "ERR …" on failure
  out="$cache/$(printf '%s\n%s\n' "$2" "$5" | sha).jsonl"
  if [ $fresh -eq 0 ] && [ -f "$out" ] && [ -n "$(find "$out" -mmin -"$ttl" 2>/dev/null)" ]; then cat "$out"; return; fi
  cmd="${2//\{target\}/\"\$KEEL_TARGET\"}"
  ( cd "$root" && KEEL_TARGET="$4" KEEL_TARGET_KIND="$3" KEEL_TARGET_FULL="$5" bash -c "$cmd" ) > "$out.tmp" 2> "$out.err" &
  pid=$!; t=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ $t -ge $((timeout*10)) ]; then kill "$pid" 2>/dev/null; sleep 0.2; kill -9 "$pid" 2>/dev/null
      echo "ERR timed out after ${timeout}s"; rm -f "$out.tmp"; return; fi
    sleep 0.1; t=$((t+1))
  done
  if wait "$pid"; then
    grep -E '^[[:space:]]*\{.*"metric"[[:space:]]*:.*"value"[[:space:]]*:' "$out.tmp" > "$out"; rm -f "$out.tmp"; cat "$out"
  else
    echo "ERR exit $? — $(tail -1 "$out.err" | cut -c1-120)"; rm -f "$out.tmp"
  fi
}
field() { # field <json-line> <key> → value (string or number), no jq needed
  printf '%s' "$1" | awk -v k="$2" '{
    if (match($0, "\"" k "\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"")) { v=substr($0,RSTART,RLENGTH); sub(/^[^:]*:[[:space:]]*"/,"",v); sub(/"$/,"",v); print v }
    else if (match($0, "\"" k "\"[[:space:]]*:[[:space:]]*-?[0-9.]+")) { v=substr($0,RSTART,RLENGTH); sub(/^[^:]*:[[:space:]]*/,"",v); print v }
  }'
}

signals=""; zero=""
echo "usage:"
for full in "${targets[@]}"; do
  kind="${full%%:*}"; value="${full#*:}"
  [ "$kind" = "$full" ] && { kind=other; value="$full"; }
  echo "  $full"
  any=0
  while IFS="$(printf '\t')" read -r name cmd; do
    [ -z "$name" ] && continue
    res="$(run_one "$name" "$cmd" "$kind" "$value" "$full")"
    case "$res" in
      ERR*) printf '    %-9s (failed: %s)\n' "$name" "${res#ERR }"; continue ;;
      "") continue ;;
    esac
    any=1; parts=""
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      m=$(field "$line" metric); v=$(field "$line" value); l=$(field "$line" label); d=$(field "$line" detail)
      parts="${parts:+$parts · }${l:-$m} ${v}${d:+ ($d)}"
      th=$(printf '%s\n' "$thresholds" | awk -F'\t' -v m="$m" '$1==m{print $2; exit}')
      if [ -n "$th" ] && awk -v a="$v" -v b="$th" 'BEGIN{exit !(a+0 >= b+0)}'; then
        signals="$signals
signal: 2:usage: $full — $m $v ≥ $th"
      fi
      case "$m" in calls_*|requests_*|users_*|hits_*) awk -v a="$v" 'BEGIN{exit !(a+0 == 0)}' && zero="$zero
note: $full — $m is 0 (nobody uses it? safer to change, worth confirming)";; esac
    done <<EOF
$res
EOF
    printf '    %-9s %s\n' "$name" "$parts"
  done <<EOF
$sources
EOF
  [ $any -eq 1 ] || echo "    (no data)"
done
printf '%s\n' "$signals" | sed '/^$/d'
printf '%s\n' "$zero" | sed '/^$/d'
exit 0
