#!/usr/bin/env bash
# Tests for shared/prove.sh on copies of the eval fixture app (plain Node, no deps).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROVE="$ROOT/shared/prove.sh"
pass=0; fail=0

new_repo() {
  dir="$(mktemp -d 2>/dev/null || mktemp -d -t keelprove)"
  cp -R "$ROOT/evals/fixtures/base/." "$dir/"
  cd "$dir" || exit 1
  git init -q -b main; git config user.email t@t; git config user.name t
  git add -A; git commit -qm init; git checkout -qb feature
}
expect() { # expect <name> <RESULT>
  out=$(bash "$PROVE" 2>&1); got=$(printf '%s\n' "$out" | grep -Eo '^(PROVEN|NOT PROVEN|FAILING|INCONCLUSIVE|ERROR)' | head -1)
  if [ "$got" = "$2" ]; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: expected $2, got $got"; printf '%s\n' "$out" | sed 's/^/     /'; fi
  [ -z "$(git status --porcelain --ignored -- src | grep -v '^??' | grep -v '^!!')" ] || true
}

# a real fix + a test that pins it → PROVEN
new_repo
sed -i.bak 's/hour >= 18 \&\& hour < 23/hour >= 17 \&\& hour < 23/' src/pricing.js && rm src/pricing.js.bak
cat > test/pricing.test.js <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { priceFor } from '../src/pricing.js';
const at = (h) => new Date(Date.UTC(2026, 9, 14, h));
test('peak starts at 17:00 on weekdays', () => {
  assert.equal(priceFor({ start: at(17), end: at(18) }), 120000);
});
EOF
git add -A; git commit -qm "peak from 17"
expect "behavior change pinned by a new test" "PROVEN"

# same change, test that doesn't look at it → NOT PROVEN
new_repo
sed -i.bak 's/hour >= 18 \&\& hour < 23/hour >= 17 \&\& hour < 23/' src/pricing.js && rm src/pricing.js.bak
cat > test/pricing.test.js <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { priceFor } from '../src/pricing.js';
const at = (h) => new Date(Date.UTC(2026, 9, 14, h));
test('daytime is off-peak', () => {
  assert.equal(priceFor({ start: at(10), end: at(11) }), 80000);
});
EOF
git add -A; git commit -qm "peak from 17, weak test"
expect "test that doesn't exercise the change" "NOT PROVEN"

# uncommitted work is included
new_repo
sed -i.bak 's/hour >= 18 \&\& hour < 23/hour >= 17 \&\& hour < 23/' src/pricing.js && rm src/pricing.js.bak
printf '%s\n' "import { test } from 'node:test';" "import assert from 'node:assert/strict';" "import { priceFor } from '../src/pricing.js';" \
  "test('17h is peak', () => assert.equal(priceFor({ start: new Date(Date.UTC(2026,9,14,17)), end: new Date(Date.UTC(2026,9,14,18)) }), 120000));" > test/p.test.js
expect "uncommitted + untracked changes" "PROVEN"
git status --porcelain | grep -q 'src/pricing.js' && { pass=$((pass+1)); echo "ok   working tree left untouched"; } || { fail=$((fail+1)); echo "FAIL working tree was modified"; }

# only new source files → INCONCLUSIVE
new_repo
printf 'export const twice = (n) => n * 2;\n' > src/twice.js
printf '%s\n' "import { test } from 'node:test';" "import assert from 'node:assert/strict';" "import { twice } from '../src/twice.js';" "test('twice', () => assert.equal(twice(2), 4));" > test/twice.test.js
git add -A; git commit -qm twice
expect "only new files" "INCONCLUSIVE"

# tests broken by the change → FAILING
new_repo
sed -i.bak 's/if (booking.userId !== userId) throw new Error(.forbidden.);//' src/bookings.js && rm src/bookings.js.bak
git add -A; git commit -qm "drop owner check"
expect "change breaks existing tests" "FAILING"

# docs only → INCONCLUSIVE
new_repo; echo more >> README.md; git add -A; git commit -qm docs
expect "no source change" "INCONCLUSIVE"

echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
