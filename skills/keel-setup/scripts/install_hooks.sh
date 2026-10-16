#!/usr/bin/env bash
# keel · install_hooks.sh — make keel run on its own, for you in this clone (nothing committed).
#
#   install_hooks.sh --git        # git pre-push: stop unchecked HIGH/CRITICAL pushes
#   install_hooks.sh --claude     # Claude Code Stop hook: nudge when a risky change wasn't checked
#   install_hooks.sh --all
#   install_hooks.sh --uninstall
#   install_hooks.sh --status
#
# Copies the hook scripts (and risk.sh / fingerprint.sh) to <git dir>/keel/, so they keep
# working if the skill moves; re-run after updating keel. Claude Code settings go in
# .claude/settings.local.json (personal). Existing hooks are never overwritten: if you
# already have a pre-push hook (husky, lefthook…), it prints the one line to add instead.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 2; }
root=$(git rev-parse --show-toplevel); cd "$root" || exit 2
gitdir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
dest="$gitdir/keel"
hookdir=$(git rev-parse --git-path hooks); case "$hookdir" in /*) ;; *) hookdir="$root/$hookdir" ;; esac
marker="# keel pre-push"

src_of() { for d in "$here" "$here/../hooks" "$here/hooks"; do [ -f "$d/$1" ] && { echo "$d/$1"; return; }; done; echo ""; }
copy_scripts() {
  mkdir -p "$dest"
  for f in risk.sh fingerprint.sh claude-stop.sh pre-push; do
    s=$(src_of "$f"); [ -n "$s" ] || { echo "missing $f next to $0" >&2; exit 2; }
    cp "$s" "$dest/$f"; chmod +x "$dest/$f"
  done
}
settings_py() { # settings_py add|remove <file> <command>
  python3 - "$@" <<'PY'
import json, os, sys
action, path, cmd = sys.argv[1:4]
data = {}
if os.path.exists(path):
    with open(path) as f:
        txt = f.read().strip()
        data = json.loads(txt) if txt else {}
stop = data.setdefault("hooks", {}).setdefault("Stop", [])
stop[:] = [g for g in stop if not any("keel/claude-stop.sh" in h.get("command", "") for h in g.get("hooks", []))]
if action == "add":
    stop.append({"hooks": [{"type": "command", "command": cmd, "timeout": 30}]})
if not stop: del data["hooks"]["Stop"]
if not data["hooks"]: del data["hooks"]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
PY
}

install_git() {
  copy_scripts
  if git ls-files --error-unmatch "${hookdir#"$root"/}" >/dev/null 2>&1 || { [ -f "$hookdir/pre-push" ] && ! grep -q "$marker" "$hookdir/pre-push"; }; then
    echo "git: you already manage hooks ($hookdir). Add this line to your pre-push hook:"
    echo "  bash \"$dest/pre-push\" \"\$@\" || exit 1"
    return
  fi
  mkdir -p "$hookdir"
  printf '#!/usr/bin/env bash\n%s (installed by keel-setup; remove with install_hooks.sh --uninstall)\nexec bash "%s/pre-push" "$@"\n' "$marker" "$dest" > "$hookdir/pre-push"
  chmod +x "$hookdir/pre-push"
  echo "git: pre-push installed — unchecked HIGH/CRITICAL pushes stop (bypass: git push --no-verify)"
}
install_claude() {
  copy_scripts
  cmd="bash \"$dest/claude-stop.sh\""
  if command -v python3 >/dev/null; then
    settings_py add "$root/.claude/settings.local.json" "$cmd"
    # keep the personal settings file out of commits without touching the team's .gitignore
    git check-ignore -q .claude/settings.local.json 2>/dev/null || echo ".claude/settings.local.json" >> "$gitdir/info/exclude"
    echo "claude: Stop hook added to .claude/settings.local.json — restart Claude Code (or /hooks) to load it"
  else
    echo "claude: python3 not found; add this to .claude/settings.local.json yourself:"
    printf '  {"hooks":{"Stop":[{"hooks":[{"type":"command","command":%s,"timeout":30}]}]}}\n' "\"bash \\\"$dest/claude-stop.sh\\\"\""
  fi
}
uninstall() {
  [ -f "$hookdir/pre-push" ] && grep -q "$marker" "$hookdir/pre-push" && rm -f "$hookdir/pre-push" && echo "git: pre-push removed"
  if [ -f "$root/.claude/settings.local.json" ] && command -v python3 >/dev/null; then
    settings_py remove "$root/.claude/settings.local.json" "" && echo "claude: Stop hook removed"
  fi
  rm -rf "$dest"
}
status() {
  if [ -f "$hookdir/pre-push" ] && grep -q "$marker" "$hookdir/pre-push"; then echo "git pre-push: on"; else echo "git pre-push: off"; fi
  if grep -q "keel/claude-stop.sh" "$root/.claude/settings.local.json" 2>/dev/null; then echo "claude stop hook: on"; else echo "claude stop hook: off"; fi
}

case "${1:-}" in
  --git) install_git ;;
  --claude) install_claude ;;
  --all) install_git; install_claude ;;
  --uninstall) uninstall ;;
  --status) status ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
