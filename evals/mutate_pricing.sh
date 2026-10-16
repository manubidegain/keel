#!/usr/bin/env bash
# Independent check for the keel-tests eval: apply known bugs to src/pricing.js one at a
# time and count how many the newly written tests catch. Restores the file afterwards.
# Usage: mutate_pricing.sh <repo>
set -u
cd "${1:?repo}" || exit 1
f=src/pricing.js
[ -z "$(git diff --name-only -- src)" ] || { echo "FAIL: src/ was left modified by the run:"; git diff --stat -- src; }
new_tests=$(git status --porcelain -- test | awk '{print $2}' | grep '\.js$' | tr '\n' ' ')
[ -n "$new_tests" ] || { echo "no new test files"; exit 1; }
echo "new tests: $new_tests"
node --test $new_tests >/dev/null 2>&1 && echo "baseline: pass" || { echo "baseline: FAIL (tests fail on correct code)"; exit 1; }

cp "$f" "$f.orig"
killed=0; total=0
mutate() { # name, perl substitution
  total=$((total+1))
  cp "$f.orig" "$f"; perl -0pi -e "$2" "$f"
  if cmp -s "$f" "$f.orig"; then echo "  ?? $1 (mutation did not apply)"; return; fi
  if node --test $new_tests >/dev/null 2>&1; then echo "  survived  $1"; else echo "  killed    $1"; killed=$((killed+1)); fi
}
mutate "peak starts at 19 instead of 18 (hour > 18)" 's/hour >= 18/hour > 18/'
mutate "peak ends at 24 instead of 23 (hour <= 23)"  's/hour < 23/hour <= 23/'
mutate "weekends not peak"                          's/day === 0 \|\| day === 6 \|\| //'
mutate "only Sunday counts as weekend"              's/ \|\| day === 6//'
mutate "peak price wrong"                           's/120000/100000/'
mutate "bills one extra hour (t <= end)"            's/t < end/t <= end/'
mutate "uses local time instead of UTC"             's/getUTCHours/getHours/'
cp "$f.orig" "$f"; rm -f "$f.orig"
echo "mutation score: $killed/$total"
