#!/usr/bin/env bash
# Tests for find_culprit.sh and replay.sh.
set -u
SH="$(cd "$(dirname "$0")/.." && pwd)/shared"
pass=0; fail=0
dir="$(mktemp -d 2>/dev/null || mktemp -d -t keeltest)"; cd "$dir" || exit 1
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; printf '%s\n' "${2:-}" | sed 's/^/     /'; }
has() { printf '%s\n' "$2" | grep -Eq -- "$3" && ok "$1" || bad "$1" "$2"; }
c() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -qam "$2"; }

git init -q -b main; git config user.email t@t; git config user.name t
mkdir -p src/payments
cat > src/payments/refund.js <<'J'
export async function refund(booking, db) {
  if (booking.status === 'cancelled') throw new Error('already cancelled');
  await db.credit(booking.userId, booking.amountCents);
}
J
echo '# app' > README.md; git add -A; c "2026-10-01T10:00:00" "init"
echo 'more docs' >> README.md; c "2026-10-05T10:00:00" "docs (#11)"
sed -i.bak '/already cancelled/d' src/payments/refund.js; rm -f src/payments/refund.js.bak
c "2026-10-08T10:00:00" "simplify refund (#12)"
echo 'export const x = 1' > src/util.js; git add -A; c "2026-10-09T10:00:00" "util (#13)"

out=$(bash "$SH/find_culprit.sh" --file src/payments/refund.js:2 --symbol "already cancelled" --since 2026-10-02)
top=$(printf '%s\n' "$out" | head -1)
has "the commit that removed the check ranks first" "$top" "simplify refund \(#12\)"
has "evidence is explained" "$out" "added/removed uses of already cancelled"
has "tier keel would have given at the time, with PR" "$out" "keel would have said: high · PR #12"
printf '%s\n' "$out" | grep -q "util (#13)" && bad "unrelated commits are not candidates" "$out" || ok "unrelated commits are not candidates"
bash "$SH/find_culprit.sh" --file nope.js --since 2026-10-02 >/dev/null; [ $? -eq 1 ] && ok "no evidence → says so" || bad "no evidence → says so"

# replay
mkdir -p .agents/keel-cases/2026-10-15-double-refund
git show --format= HEAD~1 > .agents/keel-cases/2026-10-15-double-refund/change.diff
printf 'expect: high\nRefunds were credited twice after the status check was removed.\n' > .agents/keel-cases/2026-10-15-double-refund/case.md
out=$(bash "$SH/replay.sh"); code=$?
[ $code -eq 0 ] && has "replay: incident still flagged" "$out" "^ok +2026-10-15-double-refund: high" || bad "replay ok" "$out"
printf 'relaxed:\n  - "src/payments/**"\n' > .agents/keel.yaml
out=$(bash "$SH/replay.sh"); code=$?
[ $code -eq 1 ] && has "replay: a policy change that hides it fails" "$out" "^MISS" || bad "replay miss" "$out"

rm -rf "$dir"
echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
