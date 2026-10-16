#!/usr/bin/env bash
# keel · plan_ui.sh — open a plan in Plannotator (https://plannotator.ai) with keel's notes
# already pinned to the text they're about, so the user can answer, edit or approve it visually.
# Optional: everything works without it; keel falls back to the terminal.
#
# Usage:
#   plan_ui.sh open <plan.md> <notes.txt>
#       → starts the session in the background, pins the notes, prints `url:` and
#         `result: <file>` and returns immediately. exit 3 = plannotator not installed.
#   plan_ui.sh wait <result-file> [--timeout <seconds>]
#       → waits for the user's decision and prints its JSON:
#         {"decision": "approved" | "annotated" | "dismissed", "feedback": "..."}
#         exit 0 = decided, 4 = still open (timeout).
#
# notes.txt (written by keel):
#   === general
#   A note about the whole plan…
#   === on drops the legacy_notes column
#   A note pinned to that exact phrase of the plan (as rendered: no backticks, no **).
#
# Needs: plannotator (curl -fsSL https://plannotator.ai/install.sh | bash), curl.
set -u
cmd="${1:-}"; shift || true

json_str() { printf '%s' "$1" | awk 'BEGIN{ORS=""; printf "\""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r"); if (NR>1) printf "\\n"; print} END{printf "\""}'; }

case "$cmd" in
open)
  plan="${1:?usage: plan_ui.sh open <plan.md> <notes.txt>}"; notes="${2:?notes file}"
  command -v plannotator >/dev/null || { echo "plannotator not installed (https://plannotator.ai) — use the terminal flow" >&2; exit 3; }
  command -v curl >/dev/null || { echo "curl not found" >&2; exit 2; }
  [ -f "$plan" ] || { echo "no plan file: $plan" >&2; exit 2; }
  [ -f "$notes" ] || { echo "no notes file: $notes" >&2; exit 2; }

  dir="$(cd "$(dirname "$plan")" && pwd)/plan-ui"; mkdir -p "$dir"
  ready="$dir/ready.json"; result="$dir/result.json"; rm -f "$ready" "$result" "$result.tmp"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/started_at"

  # notes.txt → annotations
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"
  awk -v T="$tmp" '
    /^=== general[[:space:]]*$/ { n++; print "" > (T "/n" n ".q"); out=T "/n" n ".md"; printf "" > out; next }
    /^=== on / { n++; q=substr($0,8); print q > (T "/n" n ".q"); out=T "/n" n ".md"; printf "" > out; next }
    { if (out) print > out }
  ' "$notes"
  items=""
  for q in "$tmp"/n*.q; do
    [ -e "$q" ] || break
    md="${q%.q}.md"; quote=$(cat "$q"); text=$(awk 'NF{p=1} p' "$md")
    [ -n "$text" ] || continue
    if [ -n "$quote" ]; then
      a="{\"source\":\"keel\",\"type\":\"COMMENT\",\"originalText\":$(json_str "$quote"),\"text\":$(json_str "$text")}"
    else
      a="{\"source\":\"keel\",\"type\":\"GLOBAL_COMMENT\",\"text\":$(json_str "$text")}"
    fi
    items="${items:+$items,}$a"
  done
  printf '{"annotations":[%s]}\n' "$items" > "$dir/annotations.json"
  rm -rf "$tmp"

  # --gate adds Approve next to Send Feedback; the result file is written once, atomically
  PLANNOTATOR_READY_FILE="$ready" nohup plannotator annotate "$plan" --gate --json --result-file "$result" \
    > "$dir/stdout.json" 2> "$dir/plannotator.log" &
  echo $! > "$dir/pid"
  i=0; while [ ! -s "$ready" ] && [ $i -lt 120 ]; do sleep 0.5; i=$((i+1)); done
  [ -s "$ready" ] || { echo "plannotator did not start; see $dir/plannotator.log" >&2; tail -5 "$dir/plannotator.log" >&2; exit 2; }
  url=$(sed -nE 's/.*"url" *: *"([^"]+)".*/\1/p' "$ready" | head -1)
  port=$(sed -nE 's/.*"port" *: *([0-9]+).*/\1/p' "$ready" | head -1)

  if [ -n "$items" ]; then
    code=0; i=0
    while [ $i -lt 20 ]; do
      code=$(curl -s -o "$dir/post.out" -w '%{http_code}' -X POST "http://127.0.0.1:$port/api/external-annotations" \
        -H 'Content-Type: application/json' --data-binary "@$dir/annotations.json")
      [ "$code" = 201 ] && break
      sleep 0.5; i=$((i+1))
    done
    [ "$code" = 201 ] || { echo "could not pin notes (HTTP $code): $(cat "$dir/post.out")" >&2; exit 2; }
  fi
  n=$(grep -o '"source":"keel"' "$dir/annotations.json" | wc -l | tr -d ' ')
  echo "url: $url"
  echo "notes: $n"
  echo "result: $result"
  ;;
wait)
  result="${1:?usage: plan_ui.sh wait <result-file> [--timeout s]}"; shift
  timeout=540; [ "${1:-}" = "--timeout" ] && timeout="$2"
  dir="$(dirname "$result")"
  i=0
  while [ ! -s "$result" ] && [ $i -lt "$timeout" ]; do
    # closed without a decision: the process is gone and no result was written
    if [ -f "$dir/pid" ] && ! kill -0 "$(cat "$dir/pid")" 2>/dev/null; then
      [ -s "$dir/stdout.json" ] && { cat "$dir/stdout.json"; exit 0; }
      echo '{"decision":"dismissed"}'; exit 0
    fi
    sleep 1; i=$((i+1))
  done
  [ -s "$result" ] || { echo '{"decision":"pending"}'; exit 4; }
  cat "$result"; echo
  ;;
*)
  sed -n '2,22p' "$0"; exit 2 ;;
esac
