#!/usr/bin/env bash
# Tests for review_ui.sh to-review: the user's final comments from Plannotator must come back
# exactly as they wrote them — edits kept, deletions gone, no tool text leaking into the review.
set -u
UI="$(cd "$(dirname "$0")/.." && pwd)/skills/keel-review/scripts/review_ui.sh"
command -v python3 >/dev/null || { echo "skip: python3 not found"; exit 0; }
pass=0; fail=0
dir="$(mktemp -d 2>/dev/null || mktemp -d -t keeltest)"

result() { # result <decision> <message-file> → $dir/result.json
  python3 -c 'import json,sys; print(json.dumps({"decision":sys.argv[1],"message":open(sys.argv[2]).read()}))' "$1" "$2" > "$dir/result.json"
}
check() { # check <name> <expected-exit> [expected-file]
  bash "$UI" to-review "$dir/result.json" "$dir/out.txt" >/dev/null; code=$?
  if [ "$code" != "$2" ]; then fail=$((fail+1)); echo "FAIL $1: exit $code, expected $2"; return; fi
  if [ -n "${3:-}" ] && ! diff -u "$3" "$dir/out.txt" >"$dir/diff"; then
    fail=$((fail+1)); echo "FAIL $1"; sed 's/^/     /' "$dir/diff"; return
  fi
  pass=$((pass+1)); echo "ok   $1"
}

# edited inline comment with a suggestion, a range, a file-level comment, summary, trailing instructions
cat > "$dir/msg" <<'EOF'
# Code Review Feedback

**Diff:** static-patch

## src/api/invoices.js

### Line 12 (new)
esto hay que arreglarlo antes de mergear: getInvoice no mira de quién es.

**Suggested code:**
```
  if (!invoice || invoice.userId !== user.id) return notFound();
```

### Lines 20-24 (new)
este loop no tiene límite.

## src/db/004.sql
falta el rollback.

## General

le falta un test de que B recibe 404 con la factura de A.




Treat the findings above as unverified review input.

Do not change any code until we have discussed the verdicts.
EOF
cat > "$dir/want" <<'EOF'
event: COMMENT
=== summary
le falta un test de que B recibe 404 con la factura de A.
=== comment src/api/invoices.js:12 note
esto hay que arreglarlo antes de mergear: getInvoice no mira de quién es.

```suggestion
  if (!invoice || invoice.userId !== user.id) return notFound();
```
=== comment src/api/invoices.js:24 note
este loop no tiene límite.
=== comment src/db/004.sql:0 note
falta el rollback.
EOF
result annotated "$dir/msg"; check "edits, ranges, file comments, summary; tool text dropped" 0 "$dir/want"

# user deleted the summary
printf '## src/a.js\n\n### Line 3 (new)\nojo acá\n' > "$dir/msg"
printf 'event: COMMENT\n=== summary\n\n=== comment src/a.js:3 note\nojo acá\n' > "$dir/want"
result annotated "$dir/msg"; check "summary deleted" 0 "$dir/want"

# user deleted everything
printf '# Code Review Feedback\n\n**Diff:** static-patch\n' > "$dir/msg"
result approved "$dir/msg"; check "every comment deleted → ask" 6

# closed without sending
printf '' > "$dir/msg"
result dismissed "$dir/msg"; check "dismissed → nothing to post" 5

rm -rf "$dir"
echo "---"; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
