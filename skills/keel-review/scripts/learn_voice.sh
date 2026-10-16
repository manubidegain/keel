#!/usr/bin/env bash
# keel · learn_voice.sh — collect the user's own past review comments so keel can write like them.
#
# Usage: learn_voice.sh [--limit-prs 40] [--out ~/.config/keel/voice-samples.md]
# Needs: gh logged in as the user. Reads only; writes one local file (never committed).
# Then the agent writes ~/.config/keel/voice.md from the samples (see references/voice.md).
set -u
limit=40
out="${KEEL_VOICE_SAMPLES:-$HOME/.config/keel/voice-samples.md}"
while [ $# -gt 0 ]; do
  case "$1" in --limit-prs) limit="$2"; shift 2;; --out) out="$2"; shift 2;; *) echo "unknown arg $1" >&2; exit 2;; esac
done
command -v gh >/dev/null || { echo "gh CLI not found" >&2; exit 2; }
me=$(gh api user --jq .login) || { echo "gh is not logged in" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"; trap 'rm -rf "$tmp"' EXIT

# PRs the user reviewed or commented on, most recent first
gh api "search/issues?q=type:pr+commenter:$me+-author:$me&sort=updated&order=desc&per_page=$limit" \
  --jq '.items[] | .pull_request.url' > "$tmp/prs" 2>/dev/null || true
gh api "search/issues?q=type:pr+reviewed-by:$me+-author:$me&sort=updated&order=desc&per_page=$limit" \
  --jq '.items[] | .pull_request.url' >> "$tmp/prs" 2>/dev/null || true
sort -u "$tmp/prs" | head -"$limit" > "$tmp/prs.u"
[ -s "$tmp/prs.u" ] || { echo "no reviewed PRs found for $me" >&2; exit 1; }

sel=".user.login == \"$me\" and (.body // \"\") != \"\""
n=0
{
  echo "# Review comments written by $me (raw samples for the voice profile)"
  while IFS= read -r api; do
    path=${api#https://api.github.com/}           # repos/o/r/pulls/n
    issue=$(printf '%s' "$path" | sed 's#/pulls/#/issues/#')
    echo; echo "## $path"
    gh api "$path/comments" --paginate --jq ".[] | select($sel) | \"- inline: \" + (.body | gsub(\"\\r\"; \"\"))" 2>/dev/null
    gh api "$path/reviews" --paginate --jq ".[] | select($sel) | \"- review (\" + .state + \"): \" + (.body | gsub(\"\\r\"; \"\"))" 2>/dev/null
    gh api "$issue/comments" --paginate --jq ".[] | select($sel) | \"- comment: \" + (.body | gsub(\"\\r\"; \"\"))" 2>/dev/null
    n=$((n+1))
  done < "$tmp/prs.u"
} > "$out"

count=$(grep -c '^- \(inline\|review\|comment\)' "$out" || true)
echo "collected $count comments from $n PRs → $out"
[ "$count" -lt 15 ] && echo "note: few samples; the profile will be rough — it improves as you edit drafts"
exit 0
