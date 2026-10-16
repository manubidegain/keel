#!/usr/bin/env bash
# keel · plan_risk.sh — classify the risk of a PLAN before any code is written, and list what
# a plan at that risk has to answer. No AI, just signals; the agent makes the judgment.
#
# Usage: plan_risk.sh <plan.md> [--policy <file>] [--json]
#
# Reads the files the plan names (same path rules and policy as risk.sh) and what it says it
# will do (drop a column, new endpoint, touch payments…; English and Spanish wording).
# Prints the tier, why, and an "answers" checklist: ✓ the plan covers it, ✗ it doesn't.
# Portable: bash 3.2+, awk, grep.
set -u
plan="${1:?usage: plan_risk.sh <plan.md> [--policy <file>] [--json]}"; shift
[ -f "$plan" ] || { echo "no plan file: $plan" >&2; exit 2; }
pass=()
json=0
while [ $# -gt 0 ]; do
  case "$1" in
    --policy) pass+=(--policy "$2"); shift 2 ;;
    --json) json=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"
trap 'rm -rf "$tmp"' EXIT

# plan text, lowercased, without code fences' backticks
tr '[:upper:]' '[:lower:]' < "$plan" | sed 's/`//g' > "$tmp/plan"
has() { grep -Eq "$1" "$tmp/plan"; }

# ---------------------------------------------------------------- files the plan names
# tokens that look like repo paths: contain a "/" or a file extension; not URLs or routes
grep -Eo '[A-Za-z0-9_.@-]+(/[A-Za-z0-9_.@*-]+)+/?|[A-Za-z0-9_-]+\.(js|jsx|ts|tsx|mjs|cjs|py|go|rb|php|java|kt|swift|rs|dart|cs|vue|svelte|sql|prisma|ya?ml|json|toml|tf|proto|graphql|env)' "$plan" \
  | grep -Ev '^(https?|www\.)|^[0-9.]+$' | sort -u > "$tmp/paths" || true
: > "$tmp/diff"
while IFS= read -r p; do
  printf 'diff --git a/%s b/%s\n--- /dev/null\n+++ b/%s\n' "$p" "$p" "$p" >> "$tmp/diff"
done < "$tmp/paths"

# ---------------------------------------------------------------- what the plan says it will do
sig=()
add() { sig+=(--signal "$1:$2"); intents="${intents:-} $3"; }
intents=""
w='(^|[^a-z])'   # word start
e='([^a-z]|$)'   # word end
has "${w}(drop|dropping|truncat)[a-z]*[^.;]{0,40}(column|columna|table|tabla|schema|database|base de datos)" \
  && add 3 "plan: irreversible data operation (drop/truncate)" destructive
dbctx="${w}(migrations?|migraci(o|ó)n|migrate|schema|esquema|sql|database|base de datos|db|supabase|prisma|postgres|mysql)${e}"
has "${w}(remov|delet|elimin|borr|quit|renam|renombr)[a-z]*[^.;]{0,40}(column|columna)" && has "$dbctx" \
  && add 3 "plan: removes or renames a column" destructive
has "${w}(delete|deleting|remove|removes|removing|borrar|borra|eliminar|elimina|purge|purgar|wipe)[a-z]*[^.;]{0,40}(rows|records|registros|datos|data|older than|m(a|á)s (viejos?|antiguos?) (de|que)|de m(a|á)s de [0-9un])" \
  && add 3 "plan: deletes existing data" destructive
has "${w}(backfill|bulk update|mass update|actualizaci(o|ó)n masiva|all (the )?(users|rows|records)|todos los (usuarios|registros))" \
  && add 2 "plan: changes existing data in bulk" bulk
has "${w}(migration|migraci(o|ó)n|migrate|schema|esquema|add (a )?column|agregar (una )?columna|nueva columna|new column|new table|nueva tabla|(add|create|new|crear|agregar|nuevo) (an? |un )?(index|(i|í)ndice))" \
  && add 2 "plan: database migration/schema" migration
has "${w}(auth|authentication|autenticaci(o|ó)n|login|logout|sessions?|sesi(o|ó)n|password|contraseña|permissions?|permisos?|roles?|rol|admin|tokens?|oauth|sso|jwt|rls|row.level)${e}" \
  && add 2 "plan: auth/permissions" auth
has "${w}(payments?|pagos?|refunds?|reembolsos?|charges?|cobros?|cobrar|invoices?|facturas?|billing|facturaci(o|ó)n|checkout|stripe|mercadopago|payouts?|wallet)" \
  && add 2 "plan: payments/money" money
has "${w}(precios?|prices?|pricing|tarifas?|saldo|balance|descuentos?|discounts?|credits?|cr(e|é)ditos?)${e}" \
  && add 1 "money-related logic in the plan" price
has "${w}(new endpoint|endpoint nuevo|nuevo endpoint|public api|api p(u|ú)blica|(get|post|put|patch|delete) /|new route|nueva ruta|graphql|openapi|breaking change|api contract|contrato de (la )?api|response shape|formato de respuesta)" \
  && add 2 "plan: public API/contract" api
has "${w}(deploy|ci|pipeline|github actions|workflow|docker|terraform|kubernetes|infra|env var|variable de entorno|environment variable|\.env|secrets?|secretos?)${e}" \
  && add 2 "plan: infra/CI/deploy" infra
{ has "${w}(send|sends|sending|enviar|env(i|í)a|mandar|manda|notify|notificar|avisar)[a-z]*[^.;]{0,30}(emails?|e-mails?|mails?|sms|push|notifications?|notificaci(o|ó)n|mensajes?|messages?)" \
  || has "${w}(cron|jobs?|queues?|colas?|workers?|webhooks?|scheduled|programad[oa]s?|mailer)${e}"; } \
  && add 1 "jobs/webhooks/notifications (side effects) in the plan" sidefx
{ has "${w}(add|adds|adding|agregar|agrega|new|nueva|nuevo|upgrade|upgrading|actualizar|bump|install|instalar|replace|reemplazar|cambiar)[a-z]*[^.;]{0,20}(dependency|dependencies|dependencia|library|librer(i|í)a|package|paquete|sdk)" \
  || has "${w}(npm|pnpm|yarn|bun) (install|add|i) [a-z@]|pip install [a-z]"; } \
  && add 1 "dependencies in the plan" deps

# ---------------------------------------------------------------- tier (path rules + policy + freeze live in risk.sh)
bash "$here/risk.sh" --diff-file "$tmp/diff" "${pass[@]+"${pass[@]}"}" "${sig[@]+"${sig[@]}"}" > "$tmp/risk"
tier=$(awk '/^tier:/{print $2}' "$tmp/risk")

# ---------------------------------------------------------------- what a plan at this tier must answer
: > "$tmp/answers"
need() { # need <ok-regex> <label>
  if has "$1"; then printf '✓\t%s\n' "$2" >> "$tmp/answers"; else printf '✗\t%s\n' "$2" >> "$tmp/answers"; fi
}
is() { case " $intents " in *" $1 "*) return 0;; esac; return 1; }
lvl=0; case "$tier" in medium) lvl=1;; high) lvl=2;; critical) lvl=3;; esac

if [ $lvl -ge 1 ]; then
  need "${w}(tests?|testing|prueba|probar|spec|e2e)" "how it will be tested"
fi
if [ $lvl -ge 2 ]; then
  need "fail[a-z]* (without|sin)|falla[a-z]* sin|(without|sin) (the |el |este )?(change|cambio)|regresi(o|ó)n|regression|edge case|caso borde|bordes?|boundary|límite|limite" "a test that fails without the change (edges, the bug it prevents)"
  need "${w}(rollback|roll back|revert|revertir|volver atr(a|á)s|deshacer|undo|feature flag|flag|kill switch)" "how to roll back"
  need "${w}(users?|usuarios?|clients?|clientes?|consumers?|consumidores|callers?|affects?|afecta|impact|impacto|who|qui(e|é)n|quienes)" "who or what it affects"
fi
is migration && need "${w}(reversible|down migration|migraci(o|ó)n (de )?(down|vuelta)|down migration|backward.compatible|compatible hacia atr(a|á)s|expand.{0,20}contract|two.step|dos pasos|concurrently|lock|bloque)" "migration is reversible / safe on a live table"
is destructive && need "${w}(backup|respaldo|snapshot|soft.delete|archiv|export|dry.run|count first|contar antes|irreversible)" "data is backed up or the delete can be undone"
is bulk && need "${w}(batch|lotes?|chunk|dry.run|staging|count|contar|idempotent|idempotente)" "bulk change is batched / dry-run first"
is api && need "${w}(auth|autenticad|permission|permiso|who can|qui(e|é)n puede|owner|due(n|ñ)o|rate.limit|l(i|í)mite de (requests|llamadas)|validat|valida)" "who can call it and what input it accepts"
is api && need "${w}(compatib|versi(o|ó)n|version|breaking|clients?|clientes?|consumers?|apps?)" "existing clients keep working"
is money && need "${w}(idempot|duplicad|duplicate|twice|dos veces|cents|centavos|rounding|redondeo|currency|moneda)" "money: duplicates, rounding and currency"
is sidefx && need "${w}(retry|reintent|idempot|duplicad|duplicate|twice|dos veces|fail|falla)" "side effect: what happens on retry or failure"
if [ $lvl -ge 3 ]; then
  need "${w}(owner|due(n|ñ)o|sign.off|aprob|approv|review by|revisa)" "who signs off"
  need "${w}(rollout|staging|gradual|por etapas|canary|feature flag|flag|ventana|window|horario|monitor)" "how it rolls out and is watched"
fi

# ---------------------------------------------------------------- output
if [ "$json" -eq 1 ]; then
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  printf '{"tier":"%s","why":[' "$tier"
  first=1
  while IFS= read -r l; do [ $first -eq 0 ] && printf ','; first=0; printf '"%s"' "$(esc "$l")"; done < <(sed -n 's/^  - //p' "$tmp/risk")
  printf '],"answers":['
  first=1
  while IFS="$(printf '\t')" read -r ok label; do
    [ $first -eq 0 ] && printf ','; first=0
    [ "$ok" = "✓" ] && b=true || b=false
    printf '{"covered":%s,"what":"%s"}' "$b" "$(esc "$label")"
  done < "$tmp/answers"
  printf ']}\n'
else
  echo "tier: $tier"
  sed -n '/^why:/,$p' "$tmp/risk"
  if [ -s "$tmp/answers" ]; then
    echo "the plan should answer:"
    sed 's/^/  /; s/\t/ /' "$tmp/answers"
  fi
fi
