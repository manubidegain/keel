#!/usr/bin/env bash
# keel · post_review.sh — post a keel review (summary + inline comments) to a GitHub PR.
#
# Usage: post_review.sh <pr-number> <review-file> [--repo owner/name] [--dry-run]
#
# review-file format (plain text, no JSON needed):
#
#   event: COMMENT                      # COMMENT | REQUEST_CHANGES | APPROVE
#   === summary
#   The review body, written as the user…
#   === comment src/auth/session.ts:42 must-fix
#   The inline comment, exactly as it should appear…
#   === comment src/db/004.sql:3 should-fix
#   …
#
# The severity after the location is for keel's own counts; it is NOT added to the comment.
# Nothing is added to what you write: no footer, no labels, no hidden markers.
# Posts with the user's own gh auth, so the review is theirs.
# Comments on lines outside the diff can't be inline on GitHub; they're appended to the
# summary instead. Comments the user already left on the same line (same first words) are
# skipped. REQUEST_CHANGES and APPROVE need --yes (the user's explicit go-ahead).
# Needs: gh, and `.keel/pr-<n>/` from fetch_pr.sh.
set -u
num="${1:?usage: post_review.sh <pr-number> <review-file> [--repo owner/name] [--dry-run] [--yes]}"
file="${2:?review file required}"; shift 2
repo=""; dry=0; yes=0
while [ $# -gt 0 ]; do
  case "$1" in --repo) repo="$2"; shift 2;; --dry-run) dry=1; shift;; --yes) yes=1; shift;; *) echo "unknown arg $1" >&2; exit 2;; esac
done
dir=".keel/pr-$num"
[ -f "$dir/lines.tsv" ] || { echo "run fetch_pr.sh $num first" >&2; exit 2; }
[ -z "$repo" ] && repo=$(sed -nE 's#.*"html_url": *"https://[^/]+/([^/]+/[^/]+)/pull/[0-9]+".*#\1#p' "$dir/meta.json" | head -1)
[ -z "$repo" ] && repo=$(git remote get-url origin 2>/dev/null | sed -E 's#^(git@|ssh://git@|https://)([^/:]+)[:/]##; s#\.git$##')
[ -n "$repo" ] || { echo "can't tell which repo — pass --repo owner/name" >&2; exit 2; }
head_sha=$(gh api "repos/$repo/pulls/$num" --jq .head.sha) || exit 1

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"; trap 'rm -rf "$tmp"' EXIT

# split the review file into summary.md and comment_<i>.{meta,md}
awk -v T="$tmp" '
  /^event:/ { sub(/^event:[[:space:]]*/,""); print > (T "/event"); next }
  /^=== summary/ { out=T "/summary.md"; next }
  /^=== comment / { n++; split(substr($0,13), a, " "); print a[1] "\t" a[2] > (T "/c" n ".meta"); out=T "/c" n ".md"; next }
  { if (out) print > out }
' "$file"
event=$(cat "$tmp/event" 2>/dev/null || echo COMMENT)
case "$event" in COMMENT|REQUEST_CHANGES|APPROVE) ;; *) echo "bad event: $event" >&2; exit 2;; esac
if [ "$event" != COMMENT ] && [ $yes -eq 0 ] && [ $dry -eq 0 ]; then
  echo "refusing to $event without --yes: approving or requesting changes needs the user's explicit OK" >&2; exit 3
fi
touch "$tmp/summary.md"

# JSON string escaping without jq/python: backslash, quote, tab, CR, newlines
json_str() { printf '%s' "$1" | awk 'BEGIN{ORS=""; printf "\""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r"); if (NR>1) printf "\\n"; print} END{printf "\""}'; }

comments=""; inline=0; moved=""; moved_n=0; skipped=0
for meta in "$tmp"/c*.meta; do
  [ -e "$meta" ] || break
  md="${meta%.meta}.md"
  loc=$(cut -f1 "$meta"); sev=$(cut -f2 "$meta")
  path="${loc%:*}"; line="${loc##*:}"
  body="$(cat "$md")"
  : "${sev:=note}"
  case "$line" in ''|*[!0-9]*) line=0;; esac
  if [ "$line" -gt 0 ] && grep -qxF "$(printf '%s\t%s' "$path" "$line")" "$dir/lines.tsv"; then
    first=$(printf '%s' "$body" | head -1 | cut -c1-60)
    if grep -F "$(printf '%s\t%s\t' "$path" "$line")" "$dir/previous_inline.tsv" 2>/dev/null | grep -qF "$first"; then
      skipped=$((skipped+1)); continue
    fi
    c="{\"path\":$(json_str "$path"),\"line\":$line,\"side\":\"RIGHT\",\"body\":$(json_str "$body")}"
    comments="${comments:+$comments,}$c"
    inline=$((inline+1))
  else
    moved="$moved
- \`$loc\`: $body"
    moved_n=$((moved_n+1))
  fi
done

summary="$(cat "$tmp/summary.md")"
[ -n "$moved" ] && summary="$summary
$moved"
# optional signature, only if the user configured one (e.g. "— Manu")
sig=$(awk '/^review:/{on=1;next} /^[^[:space:]#]/{on=0} on && /^[[:space:]]+signature:/{sub(/^[^:]*:[[:space:]]*/,""); gsub(/^["'\'']|["'\'']$/,""); print; exit}' .agents/keel.yaml 2>/dev/null)
[ -n "$sig" ] && summary="$summary

$sig"
# drop leading blank lines (e.g. the user deleted the summary and kept only comments)
summary="$(printf '%s\n' "$summary" | awk 'NF{p=1} p')"

payload="$tmp/payload.json"
printf '{"event":"%s","commit_id":"%s","body":%s,"comments":[%s]}\n' \
  "$event" "$head_sha" "$(json_str "$summary")" "$comments" > "$payload"

echo "repo: $repo  pr: #$num  event: $event"
echo "inline comments: $inline  moved to summary: $moved_n  skipped (already posted): $skipped"
if [ $dry -eq 1 ]; then
  echo "--- summary ---"; printf '%s\n' "$summary"
  cp "$payload" "$dir/payload.json"
  echo "--- dry run: nothing posted (payload saved to $dir/payload.json) ---"
  exit 0
fi
gh api --method POST "repos/$repo/pulls/$num/reviews" --input "$payload" --jq '"posted: \(.html_url)"'
