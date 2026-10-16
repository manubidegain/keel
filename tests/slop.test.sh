#!/usr/bin/env bash
# Tests for shared/slop.sh
set -u
SLOP="$(cd "$(dirname "$0")/.." && pwd)/shared/slop.sh"
pass=0; fail=0
dir="$(mktemp -d 2>/dev/null || mktemp -d -t keelslop)"; cd "$dir" || exit 1
git init -q -b main; git config user.email t@t; git config user.name t
mkdir -p src test
printf 'const legacy = x as any;\n// TODO old\n' > src/old.ts
git add -A; git commit -qm init; git checkout -qb feature

cat > src/a.ts <<'EOF'
const user = data as any;
const ok: string = value;
const n = raw as unknown as number;
function f(x: any) { return x }
// @ts-ignore
// eslint-disable-next-line no-console
console.log("here")
// TODO fix later
// TODO(ABC-123) tracked
// FIXME #42 tracked
const company = "anyone";
EOF
cat > src/b.py <<'EOF'
x = foo()  # type: ignore
import pdb; pdb.set_trace()
EOF
cat > test/a.test.ts <<'EOF'
it.only('focus', () => {})
it.skip('later', () => {})
console.log('fine in tests')
EOF
echo 'const legacy2 = 1;' >> src/old.ts

out=$(bash "$SLOP")
check() { # check <desc> <grep pattern> <expected count>
  n=$(printf '%s\n' "$out" | grep -cE "$2" || true)
  if [ "$n" -eq "$3" ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1: expected $3, got $n"; fi
}
check "type escapes (as any, as unknown as, : any)" 'type-escape' 3
check "suppressions (ts-ignore, eslint-disable, type: ignore)" 'suppression' 3
check "debug output in src, not in tests" 'debug' 2
check "untracked TODO only" 'todo' 1
check "focused test" 'focused-test' 1
check "skipped test" 'skipped-test' 1
check "pre-existing lines never reported" 'src/old.ts' 0
check "no false hit on the word 'anyone'" 'anyone' 0
check "line numbers point at the added line" '^src/a.ts:1	type-escape' 1

echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
