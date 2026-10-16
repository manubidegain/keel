#!/usr/bin/env bash
# keel · fetch_pr.sh — gather everything needed to review a pull request, without running its code.
#
# Usage: fetch_pr.sh <pr-number|pr-url> [--repo owner/name]
# Needs: gh (authenticated for private repos). Uses the REST API only.
# Writes into .keel/pr-<n>/ :
#   meta.json            PR metadata (title, body, author, base/head, fork?, files…)
#   pr.diff              unified diff
#   policy.yaml          .agents/keel.yaml from the BASE branch (if any) — never the PR's version
#   risk.txt             output of risk.sh on the diff with the base policy
#   lines.tsv            path<TAB>line for every commentable RIGHT-side line
#   previous_inline.tsv  your earlier inline comments on this PR (to avoid repeating them)
#   me                   the GitHub login keel is posting as
set -u
here="$(cd "$(dirname "$0")" && pwd)"
ref="${1:?usage: fetch_pr.sh <pr-number|url> [--repo owner/name]}"; shift
repo=""
[ "${1:-}" = "--repo" ] && { repo="$2"; shift 2; }

command -v gh >/dev/null || { echo "gh CLI not found — install https://cli.github.com or use a GitHub connector" >&2; exit 2; }

repo_from_remote() {
  git remote get-url origin 2>/dev/null | sed -E 's#^(git@|ssh://git@|https://)([^/:]+)[:/]##; s#\.git$##'
}
case "$ref" in
  http*://*/pull/*)
    repo=$(printf '%s' "$ref" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#')
    num=$(printf '%s' "$ref" | sed -E 's#.*/pull/([0-9]+).*#\1#') ;;
  *[!0-9]*|'') echo "not a PR number or URL: $ref" >&2; exit 2 ;;
  *) num="$ref"; [ -z "$repo" ] && repo="$(repo_from_remote)" ;;
esac
[ -n "$repo" ] || { echo "can't tell which repo — pass a PR URL or --repo owner/name" >&2; exit 2; }

out=".keel/pr-$num"; mkdir -p "$out"
gh api "repos/$repo/pulls/$num" > "$out/meta.json" || exit 1
gh api "repos/$repo/pulls/$num/files" --paginate --jq '.[] | [.filename, .status, .additions, .deletions] | @tsv' > "$out/files.tsv" || true
gh api -H "Accept: application/vnd.github.diff" "repos/$repo/pulls/$num" > "$out/pr.diff" || exit 1

base=$(gh api "repos/$repo/pulls/$num" --jq .base.ref)

# policy from the base branch: a PR must not be able to relax its own review rules
if gh api -H "Accept: application/vnd.github.raw" "repos/$repo/contents/.agents/keel.yaml?ref=$base" > "$out/policy.yaml" 2>/dev/null && [ -s "$out/policy.yaml" ]; then
  policy="$out/policy.yaml"
else
  rm -f "$out/policy.yaml"; policy=/dev/null
fi
bash "$here/risk.sh" --diff-file "$out/pr.diff" --policy "$policy" > "$out/risk.txt"

# commentable lines: added or context lines on the new side of each hunk
awk '
  /^diff --git /{file=""; next}
  /^\+\+\+ /{p=$0; sub(/^\+\+\+ (b\/)?/,"",p); file=(p=="/dev/null")?"":p; next}
  /^--- /{next}
  /^@@ /{ match($0, /\+[0-9]+/); ln=substr($0, RSTART+1, RLENGTH-1)+0; next }
  file=="" {next}
  /^\+/ { print file "\t" ln; ln++; next }
  /^ /  { print file "\t" ln; ln++; next }
' "$out/pr.diff" > "$out/lines.tsv"

# the user's own earlier inline comments on this PR (to avoid repeating them on re-review)
me=$(gh api user --jq .login 2>/dev/null || echo "")
gh api "repos/$repo/pulls/$num/comments" --paginate \
  --jq ".[] | select(.user.login == \"$me\") | [.path, ((.line // .original_line) | tostring), (.body | gsub(\"\\n\"; \" \"))] | @tsv" \
  > "$out/previous_inline.tsv" 2>/dev/null || : > "$out/previous_inline.tsv"
echo "$me" > "$out/me"

echo "pr: $repo#$num"
gh api "repos/$repo/pulls/$num" --jq '"title: \(.title)\nauthor: \(.user.login)\nfrom fork: \(.head.repo.full_name != .base.repo.full_name)\ndraft: \(.draft)\nstate: \(.state)\nbase: \(.base.ref) <- head: \(.head.ref) (\(.head.sha[0:7]))\nsize: \(.changed_files) files, +\(.additions)/-\(.deletions)"'
cat "$out/risk.txt"
extra=""; [ -f "$out/policy.yaml" ] && extra=", policy.yaml (from $base)"
echo "saved in $out/: meta.json, files.tsv, pr.diff, risk.txt, lines.tsv$extra"
echo "posting as: ${me:-unknown}"
[ -s "$out/previous_inline.tsv" ] && echo "your previous inline comments here: $(wc -l < "$out/previous_inline.tsv" | tr -d ' ')"
exit 0
