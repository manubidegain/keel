#!/usr/bin/env bash
# Copy shared scripts and references into each skill.
# Skills must be self-contained (installers copy each skill folder on its own), so shared
# files are duplicated. Edit them in shared/ or skills/keel-check/references/, then run this.
# CI runs `scripts/sync.sh --check` to fail if a copy drifted.
set -eu
cd "$(dirname "$0")/.."
check=0; [ "${1:-}" = "--check" ] && check=1
drift=0

copy() { # copy <src> <dst>
  if [ $check -eq 1 ]; then
    cmp -s "$1" "$2" || { echo "out of sync: $2 (source: $1)"; drift=1; }
  else
    mkdir -p "$(dirname "$2")"; cp "$1" "$2"
  fi
}

for s in keel-setup keel-check keel-review; do
  for f in detect.sh risk.sh run.sh; do copy "shared/$f" "skills/$s/scripts/$f"; done
done
for s in keel-check keel-review keel-tests; do
  for f in detect.sh prove.sh slop.sh; do copy "shared/$f" "skills/$s/scripts/$f"; done
done
for f in risk.sh plan_risk.sh; do copy "shared/$f" "skills/keel-plan/scripts/$f"; done
for f in examples/usage/*; do [ -f "$f" ] || continue; copy "$f" "skills/keel-setup/references/usage-sources/$(basename "$f")"; done
for f in install_hooks.sh fingerprint.sh usage.sh; do copy "shared/$f" "skills/keel-setup/scripts/$f"; done
for f in claude-stop.sh pre-push; do copy "shared/hooks/$f" "skills/keel-setup/scripts/$f"; done
copy shared/fingerprint.sh skills/keel-check/scripts/fingerprint.sh
for f in risk.sh find_culprit.sh replay.sh; do copy "shared/$f" "skills/keel-learn/scripts/$f"; done
for s in keel-plan keel-check keel-review; do
  for f in usage.sh targets.sh; do copy "shared/$f" "skills/$s/scripts/$f"; done
done
copy shared/run.sh skills/keel-tests/scripts/run.sh
copy shared/detect.sh skills/keel-onboard/scripts/detect.sh

copy skills/keel-check/references/tiers.md skills/keel-review/references/tiers.md
copy shared/voice.md skills/keel-check/references/voice.md
copy shared/voice.md skills/keel-review/references/voice.md
copy skills/keel-check/references/tiers.md skills/keel-plan/references/tiers.md
for f in skills/keel-check/references/standards/*.md; do
  copy "$f" "skills/keel-review/references/standards/$(basename "$f")"
  copy "$f" "skills/keel-plan/references/standards/$(basename "$f")"
done

[ $check -eq 0 ] && chmod +x skills/*/scripts/*.sh skills/keel-setup/scripts/pre-push shared/*.sh shared/hooks/* && echo "synced"
exit $drift
