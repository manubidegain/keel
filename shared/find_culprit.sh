#!/usr/bin/env bash
# keel · find_culprit.sh — which commit most likely caused an incident. Ranks candidates by
# evidence from the stack trace (file:line → blame), the code involved (symbol → pickaxe),
# the error text (→ pickaxe) and the window before it broke. Shows what tier keel would have
# given each one at the time.
#
# Usage:
#   find_culprit.sh [--file path[:line]]... [--symbol name]... [--text "error message"]...
#                   [--since 2026-10-01] [--until 2026-10-16] [--top 5]
# Output: one block per candidate: score, sha, date, subject, why, tier-at-the-time.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
files=(); symbols=(); texts=(); since=""; until_=""; top=5
while [ $# -gt 0 ]; do
  case "$1" in
    --file) files+=("$2"); shift 2 ;;
    --symbol) symbols+=("$2"); shift 2 ;;
    --text) texts+=("$2"); shift 2 ;;
    --since) since="$2"; shift 2 ;;
    --until) until_="$2"; shift 2 ;;
    --top) top="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)" || exit 2
win=(); [ -n "$since" ] && win+=(--since="$since"); [ -n "$until_" ] && win+=(--until="$until_")
tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"; trap 'rm -rf "$tmp"' EXIT
ev="$tmp/evidence"; : > "$ev"      # sha<TAB>points<TAB>why
note() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$ev"; }
rev_end="${until_:+$(git rev-list -1 --before="$until_" HEAD 2>/dev/null)}"; rev_end="${rev_end:-HEAD}"

for f in "${files[@]+"${files[@]}"}"; do
  path="${f%%:*}"; line=""; [ "$path" != "$f" ] && line="${f#*:}"; line="${line%%:*}"
  if [ -n "$line" ] && [ -f "$path" ]; then
    sha=$(git blame -L "$line,$line" --porcelain "$rev_end" -- "$path" 2>/dev/null | awk 'NR==1{print $1}')
    if [ -n "$sha" ] && [ "${sha#0000000}" = "$sha" ]; then
      # a line last touched long before the window is weaker evidence than a recent change
      if [ -n "$since" ] && ! git rev-list --since="$since" "$rev_end" | grep -qx "$sha"; then
        note "$sha" 1 "last changed $path:$line (before the window)"
      else note "$sha" 3 "last changed $path:$line"; fi
    fi
  fi
  git log "${win[@]+"${win[@]}"}" --format=%H "$rev_end" -- "$path" 2>/dev/null | head -20 | while read -r s; do
    note "$s" 1 "touched $path in the window"; done
done
for s in "${symbols[@]+"${symbols[@]}"}"; do
  git log "${win[@]+"${win[@]}"}" --format=%H -S "$s" "$rev_end" 2>/dev/null | head -10 | while read -r c; do
    note "$c" 2 "added/removed uses of $s"; done
done
for t in "${texts[@]+"${texts[@]}"}"; do
  git log --format=%H -S "$t" "$rev_end" 2>/dev/null | head -5 | while read -r c; do
    note "$c" 2 "introduced the text \"$(printf '%s' "$t" | cut -c1-40)\""; done
done
[ -s "$ev" ] || { echo "no candidates — widen --since, or pass the files/lines from the stack trace"; exit 1; }

awk -F'\t' '{ s[$1]+=$2; if (index(w[$1], $3)==0) w[$1]=(w[$1] ? w[$1] "; " : "") $3 } END { for (k in s) printf "%d\t%s\t%s\n", s[k], k, w[k] }' "$ev" \
  | while IFS="$(printf '\t')" read -r sc sh wh; do printf '%s\t%s\t%s\t%s\n' "$sc" "$(git log -1 --format=%ct "$sh")" "$sh" "$wh"; done \
  | sort -t"$(printf '\t')" -k1,1nr -k2,2nr | cut -f1,3,4 | head -"$top" > "$tmp/ranked"
while IFS="$(printf '\t')" read -r score sha why; do
  git show --no-color --format= "$sha" > "$tmp/diff" 2>/dev/null
  tier=$(bash "$here/risk.sh" --diff-file "$tmp/diff" 2>/dev/null | awk '/^tier:/{print $2}')
  pr=$(git log -1 --format=%s "$sha" | grep -Eo '#[0-9]+' | head -1)
  echo "$score  $(git log -1 --date=short --format='%h  %ad  %s' "$sha")"
  echo "     why: $why"
  echo "     keel would have said: ${tier:-?}${pr:+ · PR $pr}"
done < "$tmp/ranked"
