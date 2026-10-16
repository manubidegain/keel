#!/usr/bin/env bash
# Tests for shared/risk.sh — each case builds a throwaway git repo and checks the tier.
set -u
RISK="$(cd "$(dirname "$0")/.." && pwd)/shared/risk.sh"
pass=0; fail=0

new_repo() {
  dir="$(mktemp -d 2>/dev/null || mktemp -d -t keeltest)"
  cd "$dir" || exit 1
  git init -q -b main; git config user.email t@t; git config user.name t
  mkdir -p src; echo 'export const a = 1' > src/index.ts
  git add -A; git commit -qm init
}

expect() { # expect <name> <tier> [policy-args]
  got=$(bash "$RISK" | awk '/^tier:/{print $2}')
  if [ "$got" = "$2" ]; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1: expected $2, got $got"; bash "$RISK" | sed 's/^/     /'; fi
}

new_repo; expect "no changes" low
new_repo; mkdir docs; echo hi > docs/a.md; expect "docs only" low
new_repo; echo 'export const b = 2' >> src/index.ts; expect "small code change" low
new_repo; mkdir -p src/auth; echo 'x' > src/auth/login.ts; expect "auth path" high
new_repo; mkdir -p app/payments; echo 'x' > app/payments/charge.py; expect "payments path" high
new_repo; mkdir -p supabase/migrations; echo 'create table t(id int);' > supabase/migrations/001.sql; expect "additive migration" high
new_repo; mkdir -p db/migrate; echo 'ALTER TABLE users DROP COLUMN email;' > db/migrate/002.sql; expect "destructive migration" critical
# fake key assembled at runtime so the repo itself never contains a secret-shaped string
fake_key="sk_""live_""A1b2C3d4E5f6G7h8J9k0L1m2"
new_repo; echo "const k = \"$fake_key\"" >> src/index.ts; expect "live secret" critical
new_repo; echo 'const k = process.env.STRIPE_KEY' >> src/index.ts; expect "env reference is not a secret (payments → medium)" medium
new_repo; echo 'const u = process.env.API_URL' >> src/index.ts; expect "plain env reference" low
new_repo; printf '// price and refund helpers live elsewhere\nexport const z = 0\n' >> src/index.ts; expect "money words in comments only" low
new_repo; mkdir -p src/db; echo 'const r = await db.query(`SELECT * FROM t WHERE name = '"'"'${q}'"'"'`)' > src/db/find.js; expect "SQL built from template string" high
new_repo; mkdir -p src/x; echo 'export const refund = (u, c) => credit(u, c)' > src/x/a.js; expect "money logic outside payments path" medium
new_repo; mkdir -p .github/workflows; echo 'on: push' > .github/workflows/ci.yml; expect "CI workflow" high
new_repo; echo '{"dependencies":{"left-pad":"1.0.0"}}' > package.json; expect "dependency manifest" medium
new_repo; for i in $(seq 1 60); do echo "export const v$i = $i"; done > src/big.ts; expect "code without tests" medium
new_repo; mkdir -p src/ledger .agents; printf 'sensitive:\n  - "src/ledger/**"\n' > .agents/keel.yaml; git add -A; git commit -qm p
  echo x > src/ledger/a.ts; expect "policy sensitive glob" high
new_repo; mkdir -p src/generated/auth .agents; printf 'relaxed:\n  - "src/generated/**"\n' > .agents/keel.yaml; git add -A; git commit -qm p
  echo x > src/generated/auth/a.ts; expect "relaxed glob wins" low
new_repo; mkdir -p src/jobs .agents; printf 'project:\n  data: [personal]\n' > .agents/keel.yaml; git add -A; git commit -qm p
  echo x > src/jobs/send.ts; expect "side effects in sensitive-data project" high

new_repo; mkdir -p src/auth .agents; printf 'freeze:\n  - "Fri 16:00-Mon 08:00"\n' > .agents/keel.yaml; git add -A; git commit -qm p
  echo x > src/auth/a.ts; KEEL_NOW="Sat 10:00" expect "high change inside freeze" critical
new_repo; mkdir -p src/auth .agents; printf 'freeze:\n  - "Fri 16:00-Mon 08:00"\n' > .agents/keel.yaml; git add -A; git commit -qm p
  echo x > src/auth/a.ts; KEEL_NOW="Wed 10:00" expect "high change outside freeze" high
new_repo; mkdir -p src/docs .agents; printf 'freeze:\n  - "Fri 16:00-Mon 08:00"\n' > .agents/keel.yaml; git add -A; git commit -qm p
  echo x > src/docs/a.md; KEEL_NOW="Sat 10:00" expect "low change during freeze stays low" low
new_repo; mkdir -p src/ledger .agents; printf 'sensitive:\n  - "src/ledger/**"\n' > .agents/org.yaml; printf 'extends: org.yaml\n' > .agents/keel.yaml; git add -A; git commit -qm p
  echo x > src/ledger/a.ts; expect "sensitive glob inherited via extends" high

echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
