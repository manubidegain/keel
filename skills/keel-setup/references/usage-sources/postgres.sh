#!/usr/bin/env bash
# keel usage source: Postgres (also Supabase, Neon, RDS…). How much data a table or column
# change touches: rows, and rows that actually hold a value in that column.
#
#   usage:
#     sources:
#       data: "bash .agents/usage/postgres.sh"
#
# Env: KEEL_DATABASE_URL — use a READ-ONLY user or a replica. Needs psql.
# Handles table:<name> and column:<table>.<column>; identifiers are validated, never interpolated raw.
set -eu
url="${KEEL_DATABASE_URL:?KEEL_DATABASE_URL not set (read-only connection string)}"
command -v psql >/dev/null || { echo "psql not found" >&2; exit 2; }
kind="${KEEL_TARGET_KIND:-}"; t="${KEEL_TARGET:-}"
case "$t" in *[!A-Za-z0-9_.]*|'') exit 0 ;; esac          # only plain identifiers
q() { psql "$url" -X -A -t -v ON_ERROR_STOP=1 -c "set statement_timeout = '10s'; set default_transaction_read_only = on; $1" | tail -1; }
case "$kind" in
  table)
    rows=$(q "select reltuples::bigint from pg_class where oid = to_regclass('$t')")   # estimate, instant on big tables
    [ -n "$rows" ] && echo "{\"metric\":\"rows\",\"value\":${rows:-0},\"label\":\"rows (estimate)\"}" ;;
  column)
    table="${t%.*}"; col="${t##*.}"
    exists=$(q "select count(*) from information_schema.columns where table_name = '${table##*.}' and column_name = '$col'")
    [ "$exists" = 1 ] || exit 0
    IFS='|' read -r total filled <<EOF2
$(q "select count(*), count(\"$col\") from $table")
EOF2
    echo "{\"metric\":\"rows_with_value\",\"value\":${filled:-0},\"label\":\"rows with a value\",\"detail\":\"of ${total:-0} rows\"}" ;;
esac
