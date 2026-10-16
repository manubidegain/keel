#!/usr/bin/env bash
# keel · run.sh — run project checks quietly and report pass/fail.
#
# Usage: run.sh <check> [<check> ...]      checks: test lint typecheck build e2e
# Commands come from .agents/keel.yaml (`commands:` block), falling back to detect.sh.
# Output: one line per check (✓ / ✗ / – skipped) and, for failures, the last 40 lines
# of output. Full logs go to .keel/logs/<check>.log (gitignored by setup).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
policy=".agents/keel.yaml"
mkdir -p .keel/logs

cmd_from_policy() {
  [ -f "$policy" ] || return 0
  awk -v k="$1" '/^commands:/{on=1;next} /^[^[:space:]#]/{on=0} on {
      line=$0; sub(/^[[:space:]]+/,"",line)
      if (index(line, k":")==1) { sub(/^[^:]*:[[:space:]]*/,"",line); gsub(/^["'\'']|["'\'']$/,"",line); print line; exit }
    }' "$policy"
}
cmd_from_detect() { "$here/detect.sh" . | awk -v k="$1" -F': ' '$1==k {print substr($0, length(k)+3); exit}'; }

status=0
for check in "$@"; do
  cmd="$(cmd_from_policy "$check")"
  [ -z "$cmd" ] && cmd="$(cmd_from_detect "$check")"
  if [ -z "$cmd" ] || [ "$cmd" = "none" ]; then
    echo "– $check: no command configured"
    continue
  fi
  log=".keel/logs/$check.log"
  start=$(date +%s)
  if CI=1 sh -c "$cmd" > "$log" 2>&1; then
    echo "✓ $check ($(( $(date +%s) - start ))s) — $cmd"
  else
    status=1
    echo "✗ $check ($(( $(date +%s) - start ))s) — $cmd"
    echo "  last lines (full log: $log):"
    tail -40 "$log" | sed 's/^/    /'
  fi
done
exit $status
