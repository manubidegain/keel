#!/usr/bin/env bash
# Adds a usage source to the repo (a stand-in for PostHog) and trusts it, as if the user had.
set -eu
mkdir -p .agents/usage
cat > .agents/usage/traffic.sh <<'S'
#!/usr/bin/env bash
case "$KEEL_TARGET_KIND:$KEEL_TARGET" in
  route:*bookings*) echo '{"metric":"calls_7d","value":12000,"label":"calls/7d","detail":"courtbook-ios 2.3 41%, web 59%"}'
                    echo '{"metric":"users_7d","value":340,"label":"people/7d"}' ;;
esac
S
cat > .agents/keel.yaml <<'Y'
project:
  users: 900
  data: [personal, payments]
usage:
  sources:
    traffic: "bash .agents/usage/traffic.sh"
  high_when:
    calls_7d: 1000
Y
git add -A && git -c user.name=dev -c user.email=dev@example.com commit -qm "keel usage"
bash "$1/keel-plan/scripts/usage.sh" --trust >/dev/null
