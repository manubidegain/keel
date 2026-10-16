#!/usr/bin/env bash
# Tests for shared/plan_risk.sh — tier and "answers" checklist for written plans.
set -u
PR="$(cd "$(dirname "$0")/.." && pwd)/shared/plan_risk.sh"
pass=0; fail=0
dir="$(mktemp -d 2>/dev/null || mktemp -d -t keeltest)"; cd "$dir" || exit 1

plan() { cat > plan.md; }
expect() { # expect <name> <tier> [<grep pattern that must appear>] [<pattern that must NOT appear>]
  out=$(bash "$PR" plan.md); got=$(printf '%s\n' "$out" | awk '/^tier:/{print $2}')
  ok=1
  [ "$got" = "$2" ] || ok=0
  [ -n "${3:-}" ] && ! printf '%s\n' "$out" | grep -Eq -- "$3" && ok=0
  [ -n "${4:-}" ] && printf '%s\n' "$out" | grep -Eq -- "$4" && ok=0
  if [ $ok -eq 1 ]; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1 (expected $2${3:+, /$3/}${4:+, not /$4/})"; printf '%s\n' "$out" | sed 's/^/     /'; fi
}

plan <<'P'
Fix the typo in the onboarding copy in `src/pages/welcome.tsx` and update README.md.
P
expect "copy fix" low "" "should answer"

plan <<'P'
Add a "remember me" checkbox to the login form. Store a longer-lived session token.
Tests: login with and without the box.
P
expect "auth change" high "✗ how to roll back"

plan <<'P'
1. Migration that drops the `legacy_notes` column from `bookings` (supabase/migrations/0042.sql).
2. New endpoint `DELETE /api/clubs/:id/bookings/old` removes bookings older than 2 years.
Tests: endpoint returns 200.
P
expect "drop column + delete data, no rollback/backup" critical "✗ data is backed up" "✓ data is backed up"

plan <<'P'
Plan: borrar la columna `legacy_notes` de bookings.
- Primero backup de la tabla y migración en dos pasos (expand/contract), reversible.
- Rollback: restaurar la columna desde el backup.
- Afecta a los clubes que usan notas; avisamos antes.
- Test que falla sin el cambio: lectura de bookings sin legacy_notes.
- Owner: Manu aprueba. Rollout en staging primero y monitoreamos errores.
P
expect "spanish destructive plan that answers everything" critical "✓ data is backed up" "✗"

plan <<'P'
Send a reminder email 2 hours before each booking using a new cron job in src/jobs/reminders.ts.
P
expect "side effects only" medium "✗ side effect: what happens on retry"

plan <<'P'
Show the price per hour on the court card (src/components/CourtCard.tsx). Tests for formatting.
P
expect "price display is medium, not high" medium "✓ how it will be tested" "money: duplicates"

plan <<'P'
Add a refund button for admins in src/payments/refund.ts. Idempotency key per booking, cents only.
Rollback: feature flag. Affects club admins. Regression test: second refund fails without the change.
P
expect "payments plan with answers" high "✓ money: duplicates" "✗"

plan <<'P'
Refactor the table component to remove the unused sort column header.
P
expect "UI table is not a database" low

plan <<'P'
Document local setup in README.md: `npm install`, then `npm test`.
P
expect "npm install in docs is not a dependency change" low

plan <<'P'
Add a `stripe-node` dependency with `npm install stripe` for the new checkout.
P
expect "new dependency + checkout" high "dependencies"

plan <<'P'
Show the user's email column on the profile page (src/pages/profile.tsx).
P
expect "an email column is not a side effect" low

mkdir -p .agents; printf 'sensitive:\n  - "src/ledger/**"\n' > .agents/keel.yaml
plan <<'P'
Rewrite src/ledger/totals.ts to use integers.
P
expect "policy sensitive path named in plan" high
rm -rf .agents

rm -rf "$dir"
echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
