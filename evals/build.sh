#!/usr/bin/env bash
# Build one git repo per scenario: base on `main`, the scenario's change on branch `feature`.
# Usage: evals/build.sh <out_dir>   (expected.json is NOT copied — runs must be blind)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:?usage: build.sh <out_dir>}"
mkdir -p "$out"
for s in "$here"/scenarios/*/; do
  name=$(basename "$s"); repo="$out/$name"
  rm -rf "$repo"; cp -R "$here/fixtures/base" "$repo"
  (
    cd "$repo"
    git init -q -b main
    git -c user.name=dev -c user.email=dev@example.com add -A
    git -c user.name=dev -c user.email=dev@example.com commit -qm "initial"
    git checkout -qb feature
    cp -R "$s/change/." .
    # secret-shaped test data is generated here, never stored in the repo (keeps secret
    # scanners like GitHub push protection quiet): a random fake Stripe live key
    if grep -rlq '__FAKE_STRIPE_LIVE_KEY__' . 2>/dev/null; then
      # finite input on purpose: BSD tr never stops reading /dev/urandom when SIGPIPE is
      # ignored (as on CI runners), which hangs the build
      fake="sk_""live_$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-34)"
      grep -rl '__FAKE_STRIPE_LIVE_KEY__' . | while IFS= read -r f; do
        sed "s/__FAKE_STRIPE_LIVE_KEY__/$fake/" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      done
    fi
    git -c user.name=dev -c user.email=dev@example.com add -A
    git -c user.name=dev -c user.email=dev@example.com commit -qm "$(cat "$s/message")"
  )
  echo "built $name"
done
