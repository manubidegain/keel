#!/usr/bin/env bash
# Tests for fingerprint.sh, the Claude Code Stop hook, the git pre-push hook and the installer.
set -u
S="$(cd "$(dirname "$0")/.." && pwd)/skills/keel-setup/scripts"
pass=0; fail=0
dir="$(mktemp -d 2>/dev/null || mktemp -d -t keeltest)"
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; printf '%s\n' "${2:-}" | sed 's/^/     /'; }
has() { printf '%s\n' "$2" | grep -Eq -- "$3" && ok "$1" || bad "$1" "$2"; }
empty() { [ -z "$2" ] && ok "$1" || bad "$1" "$2"; }

git init -q --bare "$dir/remote.git"
git init -q -b main "$dir/repo"; cd "$dir/repo" || exit 1
git config user.email t@t; git config user.name t
mkdir -p src; echo 'export const a = 1' > src/index.ts; git add -A; git commit -qm init
git remote add origin "$dir/remote.git"; git push -q origin main 2>/dev/null
git checkout -qb feature
FP="$S/fingerprint.sh"; STOP="$S/claude-stop.sh"
stop() { printf '{"cwd":"%s","hook_event_name":"Stop"}' "$dir/repo" | bash "$STOP"; }

# fingerprint
mkdir -p src/auth; echo 'export const login = 1' > src/auth/login.ts
a=$(bash "$FP"); mkdir -p .keel; echo noise > .keel/x; b=$(bash "$FP")
[ "$a" = "$b" ] && ok "fingerprint ignores .keel/" || bad "fingerprint ignores .keel/"
git add -A; git commit -qm auth; c=$(bash "$FP" --rev HEAD)
[ "$a" = "$c" ] && ok "same content uncommitted or committed → same id" || bad "same id" "$a vs $c"
git reset -q --soft HEAD~1   # back to uncommitted

# stop hook
empty "low change → silent" "$(cd "$dir/repo" && git stash -q -u && stop; git stash pop -q)"
out=$(stop); has "high unchecked → one-line message" "$out" '^\{"systemMessage":"keel · HIGH — auth/permissions'
empty "second time, same change → silent" "$(stop)"
echo 'export const x = 2' >> src/auth/login.ts
has "change moves → message again" "$(stop)" 'systemMessage'
bash "$FP" --mark high ready >/dev/null
empty "checked → silent" "$(stop)"
echo 'export const y = 3' >> src/auth/login.ts
mkdir -p .agents; printf 'hooks:\n  stop: ask\n' > .agents/keel.yaml
has "ask mode → block once with a reason" "$(stop)" '^\{"decision":"block","reason":"keel: this change is HIGH'
empty "ask mode does not loop" "$(stop)"
printf 'hooks:\n  stop: off\n' > .agents/keel.yaml; echo 'export const z = 4' >> src/auth/login.ts
empty "off → silent" "$(stop)"
rm -rf .agents

# installer + pre-push
out=$(bash "$S/install_hooks.sh" --all 2>&1)
has "installer: git" "$out" "pre-push installed"
has "installer: claude" "$out" "settings.local.json"
grep -q 'keel/claude-stop.sh' .claude/settings.local.json && ok "settings.local.json has the Stop hook" || bad "settings.local.json"
git check-ignore -q .claude/settings.local.json && ok "personal settings stay out of commits" || bad "settings ignored"
git add -A; git commit -qm "auth work"
out=$(git push origin feature 2>&1); code=$?
[ $code -ne 0 ] && ok "unchecked HIGH push is stopped" || bad "unchecked HIGH push is stopped" "$out"
has "push message says why and how to bypass" "$out" "keel · HIGH — feature → feature|--no-verify"
out=$(KEEL_SKIP=1 git push -q origin feature 2>&1); [ $? -eq 0 ] && ok "KEEL_SKIP=1 bypasses" || bad "KEEL_SKIP" "$out"
echo 'export const w = 5' >> src/auth/login.ts; bash "$FP" --mark high ready >/dev/null; git commit -qam more
out=$(git push -q origin feature 2>&1); [ $? -eq 0 ] && ok "checked content pushes" || bad "checked content pushes" "$out"
git checkout -qb docs main; echo hi > NOTES.md; git add -A; git commit -qm docs
out=$(git push -q origin docs 2>&1); [ $? -eq 0 ] && ok "low change pushes" || bad "low change pushes" "$out"
has "status" "$(bash "$S/install_hooks.sh" --status)" "git pre-push: on"
bash "$S/install_hooks.sh" --uninstall >/dev/null
has "uninstall" "$(bash "$S/install_hooks.sh" --status)" "git pre-push: off"
grep -q claude-stop .claude/settings.local.json && bad "uninstall removes the Stop hook" || ok "uninstall removes the Stop hook"
# existing hook manager → never overwritten
printf '#!/bin/sh\necho mine\n' > .git/hooks/pre-push; chmod +x .git/hooks/pre-push
has "existing pre-push is kept" "$(bash "$S/install_hooks.sh" --git)" "Add this line to your pre-push hook"
grep -q mine .git/hooks/pre-push && ok "existing hook untouched" || bad "existing hook untouched"

rm -rf "$dir"
echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
