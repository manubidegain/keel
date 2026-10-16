#!/usr/bin/env bash
# keel · replay.sh — past incidents as regression tests for the policy. Each case in
# .agents/keel-cases/<name>/ holds the change that caused it (change.diff) and the minimum
# tier keel must give it (`expect: high` in case.md). Replays them with the current policy.
#
# Usage: replay.sh [cases-dir]      exit 1 if any case now gets a lower tier than expected
set -u
here="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-.agents/keel-cases}"
[ -d "$dir" ] || { echo "no cases in $dir"; exit 0; }
rank() { case "$1" in low) echo 0;; medium) echo 1;; high) echo 2;; critical) echo 3;; *) echo -1;; esac; }
fail=0; n=0
for c in "$dir"/*/; do
  [ -f "$c/change.diff" ] || continue
  n=$((n+1)); name=$(basename "$c")
  want=$(awk -F': *' 'tolower($1)=="expect"{print $2; exit}' "$c/case.md" 2>/dev/null); want=${want:-high}
  got=$(bash "$here/risk.sh" --diff-file "$c/change.diff" | awk '/^tier:/{print $2}')
  if [ "$(rank "$got")" -ge "$(rank "$want")" ]; then echo "ok    $name: $got (expect ≥ $want)"
  else echo "MISS  $name: $got (expect ≥ $want)"; fail=1; fi
done
[ $n -gt 0 ] || echo "no cases in $dir"
exit $fail
