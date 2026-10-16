#!/usr/bin/env bash
# keel · targets.sh — list what a change or plan touches that production data can tell us
# about: HTTP routes, tables, columns and exported functions. Feeds usage.sh.
#
# Usage:
#   targets.sh                    # current change (same diff as risk.sh: vs merge-base, incl. uncommitted)
#   targets.sh --base <ref>
#   targets.sh --diff-file <file> # e.g. a PR diff
#   targets.sh --plan <plan.md>   # a written plan
# Prints one target per line: route:GET /api/x · table:bookings · column:bookings.notes · symbol:priceFor
# Heuristic and cheap; the agent adds what it knows and drops what doesn't matter.
set -u
base=""; diff_file=""; plan=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --diff-file) diff_file="$2"; shift 2 ;;
    --plan) plan="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "$plan" ]; then
  [ -f "$plan" ] || { echo "no plan file: $plan" >&2; exit 2; }
  sed 's/`//g' "$plan" | awk '{print "plan\t" $0}' > "$tmp/lines"
else
  if [ -n "$diff_file" ]; then cp "$diff_file" "$tmp/diff"
  else
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 2; }
    if [ -z "$base" ]; then
      for b in origin/main origin/master main master; do
        git rev-parse --verify -q "$b" >/dev/null && { base="$(git merge-base HEAD "$b" 2>/dev/null)"; break; }
      done
      [ -z "$base" ] && base="$(git rev-parse -q --verify HEAD 2>/dev/null || true)"
    fi
    if [ -n "$base" ]; then git diff --no-color "$base" > "$tmp/diff"; else : > "$tmp/diff"; fi
    git ls-files --others --exclude-standard | grep -v '^\.keel/' | head -200 | while IFS= read -r f; do
      [ -f "$f" ] && git diff --no-color --no-index /dev/null "$f" >> "$tmp/diff" 2>/dev/null
    done
  fi
  # changed lines (added and removed) with their file; plus the file paths themselves
  awk '
    /^\+\+\+ / { p=$0; sub(/^\+\+\+ (b\/)?/, "", p); if (p != "/dev/null") { cur=p; print cur "\t#FILE" }; next }
    /^--- / { p=$0; sub(/^--- (a\/)?/, "", p); if (p != "/dev/null") { cur=p; print cur "\t#FILE" }; next }
    /^[+-]/ { print cur "\t" substr($0,2) }
  ' "$tmp/diff" > "$tmp/lines"
fi

out="$tmp/out"; : > "$out"
# routes in code: app.get('/x'), router.post("/x"), @app.get("/x"), @router.delete('/x')
grep -Eio "\.(get|post|put|patch|delete)\([[:space:]]*['\"]/[^'\"]*" "$tmp/lines" \
  | awk '{ m=$0; sub(/^\./,"",m); sub(/\(.*/,"",m); p=$0; sub(/^[^\/]*/,"",p); print "route:" toupper(m) " " p }' >> "$out"
# routes in prose / docs / plans: "GET /api/x"
grep -Eo "(GET|POST|PUT|PATCH|DELETE) /[A-Za-z0-9_./:{}\-]+" "$tmp/lines" | sed 's/^/route:/' >> "$out"
# file-based routes: Next.js app router and pages/api
grep -E $'\t#FILE$' "$tmp/lines" | cut -f1 | grep -E '(^|/)app/(.*/)?route\.(ts|js|mjs)$|(^|/)pages/api/' \
  | sed -E 's#^(.*/)?app/##; s#/?route\.(ts|js|mjs)$##; s#^(.*/)?pages/api/#api/#; s#\.(ts|js|tsx|jsx)$##; s#/index$##; s#\[([^]]+)\]#:\1#g' \
  | awk '{print "route:/" $0}' >> "$out"
# SQL: columns and tables
low="$tmp/low"; tr '[:upper:]' '[:lower:]' < "$tmp/lines" > "$low"
grep -Eo 'alter table( if exists)? [a-z_."]+ (drop|rename|add|alter)( column)?( if (not )?exists)? [a-z_"]+' "$low" \
  | sed -E 's/"//g; s/alter table( if exists)? ([a-z_.]+) (drop|rename|add|alter)( column)?( if (not )?exists)? ([a-z_]+)/column:\2.\7/' \
  | grep -Ev '\.(constraint|primary|foreign|unique|index)$' >> "$out"
grep -Eo '(drop|create|truncate|alter) table( if (not )?exists)? [a-z_."]+' "$low" \
  | sed -E 's/"//g; s/.* table( if (not )?exists)? //; s/^/table:/' >> "$out"
# plans in prose: "the legacy_notes column from bookings", "columna x de la tabla y"
grep -Eo '[a-z_]+ column (from|of|in|on) [a-z_]+' "$low" | awk '{print "column:" $4 "." $1}' >> "$out"
grep -Eo 'columna [a-z_]+ de (la tabla )?[a-z_]+' "$low" | awk '{print "column:" $NF "." $2}' >> "$out"
# exported functions whose definition changed
grep -Eo 'export (default )?(async )?function [A-Za-z0-9_]+|^[^	]*	def [a-z_][a-z0-9_]*|func (\([^)]*\) )?[A-Z][A-Za-z0-9_]*' "$tmp/lines" \
  | sed -E 's/.*(function|def|func) (\([^)]*\) )?//; s/^/symbol:/' >> "$out"

sort -u "$out" | grep -Ev '^(route:[A-Z]* *|table:|column:|symbol:)$'
