#!/usr/bin/env bash
# keel · slop.sh — mechanical signs of unproven work in the lines a change ADDS.
#
# Usage: slop.sh [--base <ref>] | [--diff-file <file>]
# Prints one line per hit:  path:line  kind  code   (nothing if clean). Exit 0 always.
# Kinds: type-escape, suppression, debug, todo, focused-test, skipped-test
# Only added lines are checked, so pre-existing code never shows up here.
set -u
base=""; diff_file=""
while [ $# -gt 0 ]; do
  case "$1" in --base) base="$2"; shift 2;; --diff-file) diff_file="$2"; shift 2;; *) echo "unknown arg $1" >&2; exit 2;; esac
done
tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"; trap 'rm -rf "$tmp"' EXIT
if [ -n "$diff_file" ]; then cp "$diff_file" "$tmp/d"
else
  if [ -z "$base" ]; then
    for b in origin/main origin/master main master; do
      if git rev-parse --verify -q "$b" >/dev/null; then base="$(git merge-base HEAD "$b" 2>/dev/null)"; break; fi
    done
  fi
  [ -n "$base" ] || base=HEAD
  git diff --no-color -U0 "$base" > "$tmp/d"
  git ls-files --others --exclude-standard | grep -v '^\.keel/' | while IFS= read -r f; do
    [ -f "$f" ] && git diff --no-color -U0 --no-index /dev/null "$f" >> "$tmp/d" 2>/dev/null
  done
fi

# path<TAB>line<TAB>text for every added line
awk '
  /^diff --git /{file=""; next}
  /^\+\+\+ /{p=$0; sub(/^\+\+\+ (b\/)?/,"",p); file=(p=="/dev/null")?"":p; next}
  /^--- /{next}
  /^@@ /{ match($0, /\+[0-9]+/); ln=substr($0, RSTART+1, RLENGTH-1)+0; next }
  file=="" {next}
  /^\+/ { print file "\t" ln "\t" substr($0,2); ln++; next }
  /^ /  { ln++; next }
' "$tmp/d" > "$tmp/added"

code='\.(js|jsx|ts|tsx|mjs|cjs|py|go|rb|php|java|kt|swift|rs|dart|cs|vue|svelte)$'
test_path='(^|/)(tests?|__tests__|spec|specs|e2e|cypress)/|[._-](test|spec)\.[a-z]+$|_test\.go$|(^|/)test_[^/]+\.py$'

awk -F'\t' -v code="$code" -v tp="$test_path" '
  function hit(kind) { t=$3; sub(/^[[:space:]]+/,"",t); if (length(t)>100) t=substr(t,1,97) "..."; printf "%s:%s\t%s\t%s\n", $1, $2, kind, t }
  $1 !~ code { next }
  {
    l=$3; istest = ($1 ~ tp)
    if (l ~ /(as[[:space:]]+any([^A-Za-z0-9_]|$)|as[[:space:]]+unknown[[:space:]]+as[[:space:]]|<any>|:[[:space:]]*any([^A-Za-z0-9_]|$)|any\[\])/ && $1 ~ /\.(ts|tsx|vue|svelte)$/) hit("type-escape")
    else if (l ~ /@ts-(ignore|nocheck)|@ts-expect-error[[:space:]]*$|#[[:space:]]*type:[[:space:]]*ignore|\/\/[[:space:]]*nolint|@SuppressWarnings|#[[:space:]]*noqa|(eslint|oxlint|biome|tslint)-(disable|ignore)/) hit("suppression")
    else if (!istest && l ~ /(^|[^A-Za-z0-9_.])(console\.(log|debug)\(|debugger;?[[:space:]]*$|var_dump\(|dd\(|binding\.pry|pdb\.set_trace\(|breakpoint\(\))/) hit("debug")
    else if (l ~ /(\/\/|#|\/\*|\*)[[:space:]]*(TODO|FIXME|HACK|XXX)/ && l !~ /(TODO|FIXME|HACK|XXX)[^A-Za-z]*(\(|\[)?([A-Z][A-Z0-9]+-[0-9]+|#[0-9]+|@[A-Za-z0-9_-]+|https?:)/) hit("todo")
    else if (istest && l ~ /(^|[^A-Za-z0-9_])(it|test|describe|context)\.only\(|(^|[^A-Za-z0-9_])f(it|describe)\(/) hit("focused-test")
    else if (istest && l ~ /(^|[^A-Za-z0-9_])(it|test|describe)\.(skip|todo)\(|(^|[^A-Za-z0-9_])x(it|describe|test)\(|@pytest\.mark\.skip|t\.Skip\(|@Disabled|@Ignore/) hit("skipped-test")
  }
' "$tmp/added"
exit 0
