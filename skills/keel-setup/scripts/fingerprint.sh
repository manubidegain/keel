#!/usr/bin/env bash
# keel · fingerprint.sh — identify exactly what was checked, so hooks know whether a change
# already went through keel-check.
#
#   fingerprint.sh                     # tree id of the working tree (incl. uncommitted and untracked, minus .keel/)
#   fingerprint.sh --rev <commit>      # tree id of a commit (what a push sends)
#   fingerprint.sh --mark <tier> <verdict>   # keel-check calls this at the end: writes .keel/checked
#   fingerprint.sh --is-checked [--rev <commit>]   # exit 0 if that exact content was checked
# Same content → same id, whether it was committed afterwards or not.
set -u
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 2; }
root=$(git rev-parse --show-toplevel); cd "$root" || exit 2

worktree_id() {
  idx="$(mktemp 2>/dev/null || mktemp -t keel)"; rm -f "$idx"
  if git rev-parse -q --verify HEAD >/dev/null; then GIT_INDEX_FILE="$idx" git read-tree HEAD
  else GIT_INDEX_FILE="$idx" git read-tree --empty; fi
  GIT_INDEX_FILE="$idx" git rm -r -q --cached --ignore-unmatch .keel >/dev/null 2>&1
  GIT_INDEX_FILE="$idx" git add -A -- . ':(exclude).keel' 2>/dev/null
  GIT_INDEX_FILE="$idx" git write-tree; rm -f "$idx"
}
rev_id() { # tree of a commit, minus .keel/ (in case it was committed)
  idx="$(mktemp 2>/dev/null || mktemp -t keel)"; rm -f "$idx"
  GIT_INDEX_FILE="$idx" git read-tree "$1" || return 1
  GIT_INDEX_FILE="$idx" git rm -r -q --cached --ignore-unmatch .keel >/dev/null 2>&1
  GIT_INDEX_FILE="$idx" git write-tree; rm -f "$idx"
}
id_for() { if [ -n "${1:-}" ]; then rev_id "$1"; else worktree_id; fi; }

case "${1:-}" in
  --mark)
    mkdir -p .keel
    printf '%s %s %s %s\n' "$(worktree_id)" "${2:-unknown}" "${3:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .keel/checked
    cat .keel/checked ;;
  --is-checked)
    rev=""; [ "${2:-}" = "--rev" ] && rev="${3:-}"
    [ -f .keel/checked ] || exit 1
    [ "$(cut -d' ' -f1 .keel/checked)" = "$(id_for "$rev")" ] ;;
  --rev) rev_id "${2:?commit}" ;;
  "") worktree_id ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
