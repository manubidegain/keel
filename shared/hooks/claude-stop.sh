#!/usr/bin/env bash
# keel · Claude Code Stop hook. When the agent finishes a turn with a HIGH or CRITICAL change
# that hasn't been through keel-check, say so — once per change, never in a loop.
# Policy (.agents/keel.yaml):  hooks: { stop: suggest }   # off | suggest | ask
#   suggest — a one-line message to you; the agent stops as usual
#   ask     — the agent is asked to run keel-check before finishing (once per exact change)
# Cheap: one git diff + grep, no AI. Any problem → silent exit 0.
here="$(cd "$(dirname "$0")" && pwd)"
input="$(cat 2>/dev/null || true)"
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
cd "${cwd:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
cd "$(git rev-parse --show-toplevel)" || exit 0

mode=$(awk '/^hooks:/{on=1;next} /^[^[:space:]#]/{on=0} on && /^[[:space:]]+stop:/{print $2; exit}' .agents/keel.yaml 2>/dev/null)
mode=${mode:-suggest}
[ "$mode" = off ] && exit 0

risk="$here/risk.sh"; fp="$here/fingerprint.sh"
[ -f "$risk" ] || risk="$here/../risk.sh"; [ -f "$fp" ] || fp="$here/../fingerprint.sh"
out=$(bash "$risk" 2>/dev/null) || exit 0
tier=$(printf '%s\n' "$out" | awk '/^tier:/{print $2}')
case "$tier" in high|critical) ;; *) exit 0 ;; esac
bash "$fp" --is-checked 2>/dev/null && exit 0
id=$(bash "$fp" 2>/dev/null) || exit 0
mkdir -p .keel
[ "$(cat .keel/stop-nudged 2>/dev/null)" = "$id" ] && exit 0
echo "$id" > .keel/stop-nudged

why=$(printf '%s\n' "$out" | sed -n 's/^  - //p' | head -1 | cut -c1-140 | sed 's/\\/\\\\/g; s/"/\\"/g')
TIER=$(printf '%s' "$tier" | tr '[:lower:]' '[:upper:]')
if [ "$mode" = ask ]; then
  printf '{"decision":"block","reason":"keel: this change is %s risk (%s) and has not been checked. Run the keel-check skill on it now, then finish."}\n' "$TIER" "$why"
else
  printf '{"systemMessage":"keel · %s — %s. Not checked yet: say \\"keel\\" before you commit."}\n' "$TIER" "$why"
fi
exit 0
