#!/usr/bin/env bash
# keel · risk.sh — classify the risk of a change from its diff. No AI, just signals.
#
# Usage:
#   risk.sh                      # current branch vs merge-base with main/master, incl. uncommitted + untracked
#   risk.sh --base <ref>         # diff against a given ref
#   risk.sh --diff-file <file>   # classify an existing unified diff (e.g. `gh pr diff 123 > pr.diff`)
#   --policy <file>              # policy file (default .agents/keel.yaml in cwd)
#   add --json for machine output
#
# Portable: bash 3.2+ (macOS default), git, awk, grep. Reads .agents/keel.yaml if present.
set -u

base=""; diff_file=""; json=0; policy_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --diff-file) diff_file="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --policy) policy_arg="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"
trap 'rm -rf "$tmp"' EXIT
diff="$tmp/diff"

# ---------------------------------------------------------------- get the diff
if [ -n "$diff_file" ]; then
  cp "$diff_file" "$diff"
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 2; }
  if [ -z "$base" ]; then
    for b in origin/main origin/master main master; do
      if git rev-parse --verify -q "$b" >/dev/null; then base="$(git merge-base HEAD "$b" 2>/dev/null)"; break; fi
    done
    [ -z "$base" ] && base="$(git rev-parse -q --verify HEAD 2>/dev/null || true)"
  fi
  if [ -n "$base" ]; then git diff --no-color "$base" > "$diff"; else : > "$diff"; fi
  # untracked files count as added
  git ls-files --others --exclude-standard | grep -v "^\.keel/" | head -200 | while IFS= read -r f; do
    [ -f "$f" ] && git diff --no-color --no-index /dev/null "$f" >> "$diff" 2>/dev/null
  done
fi

# ---------------------------------------------------------------- parse
# files.tsv: path<TAB>added<TAB>removed     added.txt: path<TAB>added line
awk -v F="$tmp/files.tsv" -v A="$tmp/added.txt" '
  function flush() { if (cur != "") printf "%s\t%d\t%d\n", cur, add, del > F }
  /^diff --git / { flush(); cur=""; add=0; del=0; next }
  /^\+\+\+ / { p=$0; sub(/^\+\+\+ (b\/)?/, "", p); if (p != "/dev/null") cur=p; next }
  /^--- / { p=$0; sub(/^--- (a\/)?/, "", p); if (cur=="" && p != "/dev/null") cur=p; next }
  /^\+/ { add++; l=substr($0,2); print cur "\t" l > A; next }
  /^-/  { del++; next }
  END { flush() }
' "$diff"
touch "$tmp/files.tsv" "$tmp/added.txt"

# ---------------------------------------------------------------- policy
policy="${policy_arg:-.agents/keel.yaml}"
yaml_list() { awk -v k="$1" '$0 ~ "^"k":" {on=1;next} /^[^[:space:]#]/{on=0} on && /^[[:space:]]*-/{sub(/^[[:space:]]*-[[:space:]]*/,""); sub(/[[:space:]]+#.*$/,""); gsub(/["'\'']/,""); print}' "$policy"; }
glob_match() { # glob_match <path> <newline-separated globs>
  _p="$1"
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    pat="${g//\*\*/*}"
    # shellcheck disable=SC2053
    [[ "$_p" == $pat ]] && { echo "$g"; return 0; }
  done <<GLOBS
$2
GLOBS
  return 1
}
user_globs=""; relaxed=""; data=""; freeze=""
read_policy() { # read_policy <file>: append its lists, first data: wins (child before parent)
  [ -f "$1" ] || return 0
  policy="$1"
  user_globs="$user_globs
$(yaml_list sensitive)"
  relaxed="$relaxed
$(yaml_list relaxed)"
  freeze="$freeze
$(yaml_list freeze)"
  [ -z "$data" ] && data=$(awk '/^[[:space:]]*data:/{sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$1")
  return 0
}
if [ -n "$policy" ] && [ -f "$policy" ]; then
  child="$policy"
  read_policy "$child"
  # extends: a local path (relative to the policy file) is merged here; remote URLs are
  # left to the agent, which fetches them (scripts never touch the network).
  parent=$(awk '/^extends:/{sub(/^extends:[[:space:]]*/,""); gsub(/["'\'']/,""); sub(/[[:space:]]+#.*$/,""); print; exit}' "$child")
  case "$parent" in
    ''|http*|github.com/*|*://*) ;;
    /*) read_policy "$parent" ;;
    *) read_policy "$(dirname "$child")/$parent" ;;
  esac
  policy="$child"
fi
user_globs=$(printf '%s\n' "$user_globs" | sed '/^$/d')
relaxed=$(printf '%s\n' "$relaxed" | sed '/^$/d')
freeze=$(printf '%s\n' "$freeze" | sed '/^$/d')

# drop relaxed paths (generated / vendored code) from everything
if [ -n "$relaxed" ]; then
  : > "$tmp/keep.tsv"; : > "$tmp/drop"
  while IFS="$(printf '\t')" read -r p a d; do
    if glob_match "$p" "$relaxed" >/dev/null; then echo "$p" >> "$tmp/drop"
    else printf '%s\t%s\t%s\n' "$p" "$a" "$d" >> "$tmp/keep.tsv"; fi
  done < "$tmp/files.tsv"
  mv "$tmp/keep.tsv" "$tmp/files.tsv"
  if [ -s "$tmp/drop" ]; then
    awk -F'\t' 'NR==FNR{d[$0]=1;next} !($1 in d)' "$tmp/drop" "$tmp/added.txt" > "$tmp/added2"
    mv "$tmp/added2" "$tmp/added.txt"
  fi
fi

files_n=$(wc -l < "$tmp/files.tsv" | tr -d ' ')
added_n=$(awk -F'\t' '{s+=$2} END{print s+0}' "$tmp/files.tsv")
removed_n=$(awk -F'\t' '{s+=$3} END{print s+0}' "$tmp/files.tsv")
cut -f1 "$tmp/files.tsv" > "$tmp/paths"

# ---------------------------------------------------------------- signals
reasons="$tmp/reasons"; : > "$reasons"
score=0   # 0 low · 1 medium · 2 high · 3 critical
bump() { [ "$1" -gt "$score" ] && score=$1; printf '%s\t%s\n' "$1" "$2" >> "$reasons"; }
matches() { grep -Ei "$1" "$tmp/paths" | head -5 | paste -sd',' - | sed 's/,/, /g'; }

hit=$(matches '(^|/)(auth|authn|authz|login|logout|session|sessions|oauth|sso|jwt|password|passwords|permission|permissions|rbac|acl|middleware)(/|\.|_|-|$)')
[ -n "$hit" ] && bump 2 "auth/permissions: $hit"
hit=$(matches '(^|/)(payment|payments|billing|checkout|stripe|mercadopago|paypal|invoice|invoices|refund|refunds|wallet|payout|payouts)(/|\.|_|-|$)')
[ -n "$hit" ] && bump 2 "payments: $hit"
hit=$(matches '(^|/)(migrations?|migrate|alembic)/|schema\.prisma$|\.sql$')
[ -n "$hit" ] && bump 2 "database migration/schema: $hit"
hit=$(matches '(^|/)(policies|rls)(/|\.)|row.level')
[ -n "$hit" ] && bump 2 "row-level security / policies: $hit"
hit=$(matches '(^|/)(terraform|infra|k8s|kubernetes|helm|deploy|deployment)/|\.tf$|(^|/)Dockerfile$|docker-compose|^\.github/workflows/|\.gitlab-ci\.yml$|(^|/)(vercel|netlify|fly)\.(json|toml)$|serverless\.yml$')
[ -n "$hit" ] && bump 2 "infra/CI/deploy: $hit"
hit=$(matches '(^|/)\.env|secrets?\.|credentials')
[ -n "$hit" ] && bump 2 "env/secrets config: $hit"
hit=$(matches '(openapi|swagger)\.(ya?ml|json)$|\.proto$|\.graphql$|(^|/)schema\.graphql|(^|/)api/v[0-9]')
[ -n "$hit" ] && bump 2 "public API/contract: $hit"
hit=$(matches '(^|/)(cron|crons|jobs|workers|queues?|webhooks?)(/|\.)|(^|/)(notifications?|emails?|mailer|push)(/|\.)')
[ -n "$hit" ] && bump 1 "jobs/webhooks/notifications (side effects): $hit"
hit=$(matches '(^|/)(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|requirements[^/]*\.txt|pyproject\.toml|poetry\.lock|uv\.lock|go\.(mod|sum)|Cargo\.(toml|lock)|Gemfile(\.lock)?|composer\.(json|lock)|pubspec\.(yaml|lock)|Podfile(\.lock)?)$')
[ -n "$hit" ] && bump 1 "dependencies: $hit"

# user-defined sensitive globs
if [ -n "$user_globs" ]; then
  while IFS= read -r p; do
    g=$(glob_match "$p" "$user_globs") && bump 2 "policy sensitive ($g): $p"
  done < "$tmp/paths"
fi

# irreversible operations in added lines
destructive=$(grep -Ei 'drop[[:space:]]+(table|column|schema|database|index)|truncate[[:space:]]|alter[[:space:]]+table.*drop|delete[[:space:]]+from[[:space:]]+[a-z_."]+[[:space:]]*;|removeColumn|dropTable|DropTable|DropColumn|rename[[:space:]]+(column|to)' "$tmp/added.txt" | cut -f1 | sort -u | head -5 | paste -sd',' - | sed 's/,/, /g')
[ -n "$destructive" ] && bump 3 "irreversible data operation (DROP/TRUNCATE/DELETE/RENAME): $destructive"

# secrets in added lines (exclude obvious placeholders)
secrets=$(grep -E 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|sk_live_[0-9a-zA-Z]{10,}|rk_live_|ghp_[0-9A-Za-z]{30,}|github_pat_|xox[baprs]-[0-9A-Za-z-]{10,}|AIza[0-9A-Za-z_-]{35}|eyJhbGciOi[0-9A-Za-z_-]{20,}\.[0-9A-Za-z_-]{20,}|(password|passwd|secret|api_?key|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"' ]{8,}["'"'"']' "$tmp/added.txt" \
  | grep -Eiv 'example|placeholder|changeme|your[_-]|xxx|<[a-z_]+>|process\.env|os\.environ|getenv|\$\{' \
  | cut -f1 | sort -u | head -5 | paste -sd',' - | sed 's/,/, /g')
[ -n "$secrets" ] && bump 3 "possible secret committed: $secrets"

# content signals — what the added code does, not where it lives (code files only, tests excluded)
code_lines="$tmp/code_added.txt"
grep -Ev '^[^	]*((^|/)(tests?|__tests__|spec|specs|e2e|cypress)/|[._-](test|spec)\.[a-z]+	|_test\.go	)' "$tmp/added.txt" \
  | grep -E '^[^	]+\.(js|jsx|ts|tsx|mjs|cjs|py|go|rb|php|java|kt|swift|rs|dart|cs|vue|svelte)	' \
  | grep -Ev '	[[:space:]]*(//|#|\*|/\*|--)' > "$code_lines" || true   # skip comment lines
content_hit() { grep -Ei "$1" "$code_lines" | cut -f1 | sort -u | head -5 | paste -sd',' - | sed 's/,/, /g'; }

hit=$(content_hit '(select|insert|update|delete)[[:space:]].*(\$\{|"[[:space:]]*\+|'"'"'[[:space:]]*\+|%s|\.format\(|f"[^"]*\{)')
[ -n "$hit" ] && bump 2 "SQL built from strings (possible injection): $hit"
hit=$(content_hit '(createHmac|timingSafeEqual|bcrypt|scrypt|argon2|jwt\.|jsonwebtoken|verify(Token|Session|Signature|Password)|isAdmin|role[[:space:]]*[!=]==?|permission|authorize)')
[ -n "$hit" ] && bump 2 "auth/crypto logic in code: $hit"
hit=$(content_hit '(refund|charge|payout|credit(_?cents)?|balance|amount_?cents|amountCents|price(_?cents)?|invoice|stripe|mercadopago|paypal)')
[ -n "$hit" ] && bump 1 "money-related logic: $hit"
hit=$(content_hit '(sendEmail|sendMail|sendSms|sendPush|webhook|setInterval|cron|schedule\()')
[ -n "$hit" ] && bump 1 "side effects (messages, webhooks, schedules): $hit"

# size
if [ "$added_n" -gt 800 ] || [ "$files_n" -gt 30 ]; then bump 1 "large change: $files_n files, +$added_n/-$removed_n"
elif [ "$added_n" -gt 300 ] || [ "$files_n" -gt 15 ]; then bump 1 "medium-size change: $files_n files, +$added_n/-$removed_n"; fi

# code changed without tests
is_test='(^|/)(tests?|__tests__|spec|specs|e2e|cypress)/|[._-](test|spec)\.[a-z]+$|_test\.go$|(^|/)test_[^/]+\.py$'
is_code='\.(js|jsx|ts|tsx|mjs|cjs|py|go|rb|php|java|kt|swift|rs|dart|cs|vue|svelte)$'
code_n=$(grep -Ev "$is_test" "$tmp/paths" | grep -Ec "$is_code")
test_n=$(grep -Ec "$is_test" "$tmp/paths")
code_add=$(grep -Ev "$is_test" "$tmp/files.tsv" | RE="$is_code" awk -F'\t' 'BEGIN{re=ENVIRON["RE"]} $1 ~ re {s+=$2} END{print s+0}')
if [ "$code_n" -gt 0 ] && [ "$test_n" -eq 0 ] && [ "$code_add" -gt 40 ]; then
  bump 1 "code changed (+$code_add lines in $code_n files) with no test changes"
fi

# data-sensitivity floor: in projects that handle sensitive data, side effects and
# dependency changes are no longer "medium" — they can leak or corrupt that data.
if [ -n "$data" ] && echo "$data" | grep -Eqi 'payment|personal|health|financial|minors|pii'; then
  if [ "$score" -eq 1 ] && grep -Eq 'jobs/webhooks|dependencies' "$reasons"; then
    bump 2 "project handles sensitive data ($data): side effects/dependencies treated as high"
  fi
fi

# docs-only / trivial
if [ "$files_n" -gt 0 ] && [ "$score" -eq 0 ]; then
  nondoc=$(grep -Evc '\.(md|mdx|txt|rst|png|jpg|jpeg|gif|svg|webp)$|(^|/)(docs?|LICENSE|CHANGELOG)' "$tmp/paths")
  [ "$nondoc" -eq 0 ] && printf '0\t%s\n' "docs/assets only" >> "$reasons"
fi

# freeze windows, weekly, local time: "Fri 16:00-Mon 08:00". KEEL_NOW="Fri 17:30" overrides (tests).
in_freeze() {
  now="${KEEL_NOW:-$(date +'%a %H:%M')}"
  mow() { # minutes-of-week for "Day HH:MM" (Mon = 0)
    d=$(printf '%s' "$1" | awk '{print tolower(substr($1,1,3))}')
    t=$(printf '%s' "$1" | awk '{print $2}')
    case "$d" in mon) n=0;; tue) n=1;; wed) n=2;; thu) n=3;; fri) n=4;; sat) n=5;; sun) n=6;; *) return 1;; esac
    h=${t%%:*}; m=${t##*:}
    echo $(( n*1440 + 10#$h*60 + 10#$m ))
  }
  cur=$(mow "$now") || return 1
  while IFS= read -r w; do
    [ -z "$w" ] && continue
    s=$(mow "${w%%-*}") || continue; e=$(mow "${w#*-}") || continue
    if [ "$s" -le "$e" ]; then [ "$cur" -ge "$s" ] && [ "$cur" -lt "$e" ] && { echo "$w"; return 0; }
    else { [ "$cur" -ge "$s" ] || [ "$cur" -lt "$e" ]; } && { echo "$w"; return 0; }; fi
  done <<FREEZE
$freeze
FREEZE
  return 1
}
if [ "$score" -eq 2 ] && [ -n "$freeze" ]; then
  w=$(in_freeze) && bump 3 "high-risk change during freeze window ($w)"
fi

case $score in 0) tier=low;; 1) tier=medium;; 2) tier=high;; 3) tier=critical;; esac

# ---------------------------------------------------------------- output
if [ "$json" -eq 1 ]; then
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  printf '{"tier":"%s","files":%s,"added":%s,"removed":%s,"code_files":%s,"test_files":%s,"reasons":[' "$tier" "$files_n" "$added_n" "$removed_n" "$code_n" "$test_n"
  first=1
  while IFS="$(printf '\t')" read -r lvl msg; do
    [ $first -eq 0 ] && printf ','; first=0
    printf '{"level":%s,"why":"%s"}' "$lvl" "$(esc "$msg")"
  done < "$reasons"
  printf '],"paths":['
  first=1
  while IFS= read -r p; do [ $first -eq 0 ] && printf ','; first=0; printf '"%s"' "$(esc "$p")"; done < "$tmp/paths"
  printf ']}\n'
else
  echo "tier: $tier"
  echo "size: $files_n files, +$added_n/-$removed_n (code files: $code_n, test files: $test_n)"
  if [ -s "$reasons" ]; then
    echo "why:"
    sort -rn "$reasons" | cut -f2 | sed 's/^/  - /'
  else
    echo "why:"; echo "  - no risk signals"
  fi
fi
