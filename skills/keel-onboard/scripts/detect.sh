#!/usr/bin/env bash
# keel · detect.sh — detect stack and the commands a project uses.
# Usage: detect.sh [repo_dir]
# Prints `key: value` lines. Empty value = not found. Never runs project code.
set -u
dir="${1:-.}"
cd "$dir" || exit 1

has() { [ -e "$1" ]; }
out() { printf '%s: %s\n' "$1" "$2"; }

stacks=""
add_stack() { stacks="${stacks:+$stacks, }$1"; }

test_cmd=""; lint_cmd=""; type_cmd=""; build_cmd=""; e2e_cmd=""

# --- JavaScript / TypeScript -------------------------------------------------
if has package.json; then
  add_stack node
  pm=npm
  has pnpm-lock.yaml && pm=pnpm
  has yarn.lock && pm=yarn
  { has bun.lockb || has bun.lock; } && pm=bun
  out package_manager "$pm"
  run="$pm run"; [ "$pm" = yarn ] && run=yarn
  script() { grep -Eq "\"$1\"[[:space:]]*:" package.json; }
  script test && test_cmd="$run test"
  script lint && lint_cmd="$run lint"
  for s in typecheck type-check tsc check-types; do script "$s" && { type_cmd="$run $s"; break; }; done
  [ -z "$type_cmd" ] && has tsconfig.json && type_cmd="npx tsc --noEmit"
  script build && build_cmd="$run build"
  for s in test:e2e e2e playwright cypress; do script "$s" && { e2e_cmd="$run $s"; break; }; done
  [ -z "$e2e_cmd" ] && ls playwright.config.* >/dev/null 2>&1 && e2e_cmd="npx playwright test"
  has tsconfig.json && add_stack typescript
  grep -q '"next"' package.json && add_stack nextjs
  grep -q '"react-native"\|"expo"' package.json && add_stack react-native
fi

# --- Python ------------------------------------------------------------------
if has pyproject.toml || has requirements.txt || has setup.py; then
  add_stack python
  if [ -z "$test_cmd" ]; then
    { has pytest.ini || grep -qs pytest pyproject.toml requirements*.txt; } && test_cmd="pytest -q"
    [ -z "$test_cmd" ] && has manage.py && test_cmd="python manage.py test"
  fi
  [ -z "$lint_cmd" ] && grep -qs ruff pyproject.toml requirements*.txt && lint_cmd="ruff check ."
  [ -z "$type_cmd" ] && grep -qs mypy pyproject.toml requirements*.txt && type_cmd="mypy ."
fi

# --- Go / Rust / Ruby / PHP / Java / Dart ------------------------------------
has go.mod && { add_stack go; : "${test_cmd:=go test ./...}"; [ -z "$lint_cmd" ] && lint_cmd="go vet ./..."; [ -z "$build_cmd" ] && build_cmd="go build ./..."; }
has Cargo.toml && { add_stack rust; [ -z "$test_cmd" ] && test_cmd="cargo test"; [ -z "$lint_cmd" ] && lint_cmd="cargo clippy -- -D warnings"; [ -z "$build_cmd" ] && build_cmd="cargo build"; }
has Gemfile && { add_stack ruby; if [ -z "$test_cmd" ]; then has spec && test_cmd="bundle exec rspec" || test_cmd="bundle exec rake test"; fi; grep -qs rubocop Gemfile && [ -z "$lint_cmd" ] && lint_cmd="bundle exec rubocop"; }
has composer.json && { add_stack php; [ -z "$test_cmd" ] && { has vendor/bin/phpunit || grep -qs phpunit composer.json; } && test_cmd="vendor/bin/phpunit"; }
{ has pom.xml && add_stack java && [ -z "$test_cmd" ] && test_cmd="mvn -q test"; } || true
{ { has build.gradle || has build.gradle.kts; } && add_stack java-gradle && [ -z "$test_cmd" ] && test_cmd="./gradlew test"; } || true
has pubspec.yaml && { add_stack dart; [ -z "$test_cmd" ] && test_cmd="flutter test"; [ -z "$lint_cmd" ] && lint_cmd="flutter analyze"; }

# --- Makefile fallbacks ------------------------------------------------------
if has Makefile; then
  mk() { grep -Eq "^$1:" Makefile; }
  [ -z "$test_cmd" ] && mk test && test_cmd="make test"
  [ -z "$lint_cmd" ] && mk lint && lint_cmd="make lint"
  [ -z "$build_cmd" ] && mk build && build_cmd="make build"
fi

out stacks "$stacks"
out test "$test_cmd"
out lint "$lint_cmd"
out typecheck "$type_cmd"
out build "$build_cmd"
out e2e "$e2e_cmd"

# --- Context hints -----------------------------------------------------------
ci=""
has .github/workflows && ci="github-actions"
has .gitlab-ci.yml && ci="${ci:+$ci, }gitlab-ci"
has .circleci && ci="${ci:+$ci, }circleci"
out ci "$ci"

deploy=""
has vercel.json && deploy="vercel"
has netlify.toml && deploy="${deploy:+$deploy, }netlify"
has fly.toml && deploy="${deploy:+$deploy, }fly"
has Dockerfile && deploy="${deploy:+$deploy, }docker"
has serverless.yml && deploy="${deploy:+$deploy, }serverless"
{ has terraform || ls ./*.tf >/dev/null 2>&1; } && deploy="${deploy:+$deploy, }terraform"
has app.json && grep -qs expo app.json && deploy="${deploy:+$deploy, }expo"
out deploy "$deploy"

migrations=""
for d in supabase/migrations prisma/migrations migrations db/migrate alembic/versions database/migrations; do
  has "$d" && migrations="${migrations:+$migrations, }$d"
done
out migrations "$migrations"

tests_dirs=""
for d in test tests __tests__ spec e2e cypress; do has "$d" && tests_dirs="${tests_dirs:+$tests_dirs, }$d"; done
out test_dirs "$tests_dirs"

has .agents/keel.yaml && out policy ".agents/keel.yaml" || out policy ""
exit 0
