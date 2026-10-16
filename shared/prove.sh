#!/usr/bin/env bash
# keel · prove.sh — do the tests actually prove the change? They should pass with it and
# FAIL without it. Works in a throwaway git worktree; your working tree is never touched.
#
# Usage: prove.sh [--base <ref>] [--cmd "<test command>"]
#   --base  what "without the change" means (default: merge-base with main/master)
#   --cmd   test command (default: commands.test from .agents/keel.yaml, else detected)
#
# What it does:
#   1. copies HEAD + your uncommitted/untracked changes into a temp worktree, runs the tests → must pass
#   2. puts back the BASE version of every modified non-test source file, runs again → should fail
# New source files are left in place (removing them would fail on import, which proves nothing).
#
# Result line (and exit code):
#   PROVEN        0  tests pass with the change and fail without it
#   NOT PROVEN    1  tests still pass without the change: they don't test it
#   FAILING       3  tests fail even with the change
#   INCONCLUSIVE  4  nothing to revert, no tests changed, or failure was a load/import error
#   ERROR         2  setup problem
set -u
here="$(cd "$(dirname "$0")" && pwd)"
base=""; cmd=""
while [ $# -gt 0 ]; do
  case "$1" in --base) base="$2"; shift 2;; --cmd) cmd="$2"; shift 2;; -h|--help) sed -n '2,20p' "$0"; exit 0;; *) echo "unknown arg $1" >&2; exit 2;; esac
done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR not a git repo"; exit 2; }
root=$(git rev-parse --show-toplevel); cd "$root" || exit 2

if [ -z "$base" ]; then
  for b in origin/main origin/master main master; do
    if git rev-parse --verify -q "$b" >/dev/null; then base="$(git merge-base HEAD "$b" 2>/dev/null)"; break; fi
  done
fi
[ -n "$base" ] || { echo "INCONCLUSIVE no base to compare against (use --base)"; exit 4; }

if [ -z "$cmd" ] && [ -f .agents/keel.yaml ]; then
  cmd=$(awk '/^commands:/{on=1;next} /^[^[:space:]#]/{on=0} on { l=$0; sub(/^[[:space:]]+/,"",l); if (index(l,"test:")==1){ sub(/^test:[[:space:]]*/,"",l); gsub(/^["'\'']|["'\'']$/,"",l); print l; exit } }' .agents/keel.yaml)
fi
[ -z "$cmd" ] && cmd=$("$here/detect.sh" . | awk -F': ' '$1=="test"{print substr($0,7); exit}')
{ [ -z "$cmd" ] || [ "$cmd" = none ]; } && { echo "INCONCLUSIVE no test command found (set commands.test)"; exit 4; }

is_test='(^|/)(tests?|__tests__|spec|specs|e2e|cypress)/|[._-](test|spec)\.[a-z]+$|_test\.go$|(^|/)test_[^/]+\.py$|(^|/)conftest\.py$'
is_code='\.(js|jsx|ts|tsx|mjs|cjs|py|go|rb|php|java|kt|swift|rs|dart|cs|vue|svelte|sql)$'

changed=$( { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u | grep -v '^\.keel/' )
tests_changed=$(printf '%s\n' "$changed" | grep -E "$is_test" || true)
src_changed=$(printf '%s\n' "$changed" | grep -Ev "$is_test" | grep -E "$is_code" || true)
[ -n "$src_changed" ] || { echo "INCONCLUSIVE no source code changed"; exit 4; }

# modified (exist in base) vs new source files
revert=""; new=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if git cat-file -e "$base:$f" 2>/dev/null; then revert="$revert$f
"; else new="$new$f
"; fi
done <<EOF
$src_changed
EOF
revert=$(printf '%s' "$revert" | sed '/^$/d'); new=$(printf '%s' "$new" | sed '/^$/d')
if [ -z "$revert" ]; then
  echo "INCONCLUSIVE all changed source files are new — nothing to revert; use keel-tests' mutation check on them"
  printf '%s\n' "$new" | sed 's/^/  new: /'
  exit 4
fi
[ -z "$tests_changed" ] && echo "note: no test files changed; checking whether existing tests notice the change"

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keelprove)"
wt="$tmp/wt"
cleanup() { git worktree remove --force "$wt" >/dev/null 2>&1; rm -rf "$tmp"; }
trap cleanup EXIT
git worktree add --detach -q "$wt" HEAD 2>/dev/null || { echo "ERROR could not create worktree"; exit 2; }
# bring uncommitted + untracked changes
git diff HEAD --binary > "$tmp/wip.patch"
[ -s "$tmp/wip.patch" ] && (cd "$wt" && git apply --whitespace=nowarn "$tmp/wip.patch") || true
git ls-files --others --exclude-standard | grep -v '^\.keel/' | while IFS= read -r f; do
  mkdir -p "$wt/$(dirname "$f")"; cp -p "$f" "$wt/$f"
done
# dependencies are usually gitignored: link them in
for d in node_modules vendor .venv venv target/debug; do
  [ -e "$d" ] && [ ! -e "$wt/$d" ] && { mkdir -p "$wt/$(dirname "$d")"; ln -s "$root/$d" "$wt/$d"; }
done

run() { (cd "$wt" && CI=1 sh -c "$cmd") > "$1" 2>&1; }
load_error='Cannot find module|ERR_MODULE_NOT_FOUND|ModuleNotFoundError|ImportError|does not provide an export|SyntaxError|cannot find package|undefined: |no such file or directory'

if ! run "$tmp/with.log"; then
  echo "FAILING tests fail even with the change — fix them first"
  tail -15 "$tmp/with.log" | sed 's/^/  | /'; exit 3
fi
while IFS= read -r f; do (cd "$wt" && git checkout -q "$base" -- "$f"); done <<EOF
$revert
EOF
if run "$tmp/without.log"; then
  echo "NOT PROVEN tests still pass with the change reverted — they don't exercise it"
  printf '%s\n' "$revert" | sed 's/^/  reverted: /'
  exit 1
fi
if grep -Eq "$load_error" "$tmp/without.log"; then
  echo "INCONCLUSIVE tests fail without the change, but on a load/import error, not on behavior"
  grep -Em3 "$load_error" "$tmp/without.log" | sed 's/^/  | /'
  exit 4
fi
echo "PROVEN tests pass with the change and fail without it"
printf '%s\n' "$revert" | sed 's/^/  reverted: /'
grep -Ei 'not ok|fail|✗|✖|assert|expected' "$tmp/without.log" | head -6 | sed 's/^/  | /'
exit 0
