#!/usr/bin/env bash
# keel · review_ui.sh — open a draft review in Plannotator (https://plannotator.ai) so the
# user can read it on the diff, edit, delete or add comments, and post it themselves.
# Optional: everything works without it; keel falls back to the terminal.
#
# Usage:
#   review_ui.sh open <review.txt> --pr <PR_URL>      # a GitHub/GitLab PR
#   review_ui.sh open <review.txt> --patch <file.diff> # any unified diff (local changes)
#       → starts the session in the background, loads the drafted comments, prints
#         `url: …` and `result: <file>` and returns immediately.
#   review_ui.sh wait <result-file> [--timeout <seconds>]
#       → waits for the user's decision; prints the JSON {decision, message}.
#         exit 0 = decided, 4 = still open (timeout), 2 = error.
#   review_ui.sh to-review <result-file> <review.txt> [--event COMMENT]
#       → writes the user's final comments back as review.txt, verbatim, for
#         post_review.sh. exit 5 = nothing to post (closed/dismissed);
#         exit 6 = decided with every comment removed (ask the user).
#   review_ui.sh posted <owner/repo> <pr-number> <ui-dir>
#       → if the user posted from Plannotator itself, prints that review's URL (exit 0);
#         exit 1 = they didn't.
#
# review.txt is the same file post_review.sh reads (=== summary / === comment path:line sev).
# Drafted comments appear as editable annotations; nothing is posted until the user
# posts from Plannotator or sends feedback back to the agent.
# Needs: plannotator (curl -fsSL https://plannotator.ai/install.sh | bash), curl.
set -u
cmd="${1:-}"; shift || true

json_str() { printf '%s' "$1" | awk 'BEGIN{ORS=""; printf "\""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r"); if (NR>1) printf "\\n"; print} END{printf "\""}'; }

case "$cmd" in
open)
  review="${1:?usage: review_ui.sh open <review.txt> --pr <url> | --patch <file>}"; shift
  target=""; patch=""
  while [ $# -gt 0 ]; do
    case "$1" in --pr) target="$2"; shift 2;; --patch) patch="$2"; shift 2;; *) echo "unknown arg $1" >&2; exit 2;; esac
  done
  { [ -n "$target" ] || [ -n "$patch" ]; } || { echo "need --pr or --patch" >&2; exit 2; }
  command -v plannotator >/dev/null || { echo "plannotator not installed (https://plannotator.ai) — use the terminal flow" >&2; exit 3; }
  command -v curl >/dev/null || { echo "curl not found" >&2; exit 2; }
  [ -f "$review" ] || { echo "no review file: $review" >&2; exit 2; }

  dir="$(cd "$(dirname "$review")" && pwd)/ui"; mkdir -p "$dir"
  ready="$dir/ready.json"; result="$dir/result.json"; rm -f "$ready" "$result"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/started_at"

  # build the annotations payload from review.txt
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t keel)"
  awk -v T="$tmp" '
    /^event:/ { next }
    /^=== summary/ { out=T "/summary"; next }
    /^=== comment / { n++; split(substr($0,13), a, " "); print a[1] > (T "/c" n ".loc"); out=T "/c" n ".md"; next }
    { if (out) print > out }
  ' "$review"
  items=""
  add() { items="${items:+$items,}$1"; }
  if [ -s "$tmp/summary" ]; then
    add "{\"source\":\"draft\",\"scope\":\"general\",\"type\":\"comment\",\"text\":$(json_str "$(cat "$tmp/summary")")}"
  fi
  for loc in "$tmp"/c*.loc; do
    [ -e "$loc" ] || break
    md="${loc%.loc}.md"; l=$(cat "$loc"); path="${l%:*}"; line="${l##*:}"
    case "$line" in ''|*[!0-9]*) line=0;; esac
    # split a ```suggestion block out of the text
    text=$(awk '/^```suggestion/{s=1;next} s&&/^```/{s=0;next} !s' "$md")
    sugg=$(awk '/^```suggestion/{s=1;next} s&&/^```/{s=0;next} s' "$md")
    extra=""; [ -n "$sugg" ] && extra=",\"suggestedCode\":$(json_str "$sugg")"
    if [ "$line" -gt 0 ]; then
      add "{\"source\":\"draft\",\"scope\":\"line\",\"type\":\"comment\",\"filePath\":$(json_str "$path"),\"lineStart\":$line,\"lineEnd\":$line,\"side\":\"new\",\"text\":$(json_str "$text")$extra}"
    else
      add "{\"source\":\"draft\",\"scope\":\"file\",\"type\":\"comment\",\"filePath\":$(json_str "$path"),\"text\":$(json_str "$text")$extra}"
    fi
  done
  printf '{"annotations":[%s]}\n' "$items" > "$dir/annotations.json"
  rm -rf "$tmp"

  # start the review session in the background
  if [ -n "$patch" ]; then set -- review --patch-file "$patch" --json; else set -- review "$target" --json; fi
  PLANNOTATOR_READY_FILE="$ready" nohup plannotator "$@" > "$result.tmp" 2> "$dir/plannotator.log" &
  echo $! > "$dir/pid"
  # rename to result.json only once the process has exited (so "wait" can tell)
  ( pid=$(cat "$dir/pid"); while kill -0 "$pid" 2>/dev/null; do sleep 1; done; mv "$result.tmp" "$result" ) >/dev/null 2>&1 &

  i=0; while [ ! -s "$ready" ] && [ $i -lt 120 ]; do sleep 0.5; i=$((i+1)); done
  [ -s "$ready" ] || { echo "plannotator did not start; see $dir/plannotator.log" >&2; tail -5 "$dir/plannotator.log" >&2; exit 2; }
  url=$(sed -nE 's/.*"url" *: *"([^"]+)".*/\1/p' "$ready" | head -1)
  port=$(sed -nE 's/.*"port" *: *([0-9]+).*/\1/p' "$ready" | head -1)
  base="http://127.0.0.1:$port"

  # load the drafted comments (retry briefly while the diff loads)
  code=0; i=0
  while [ $i -lt 20 ]; do
    code=$(curl -s -o "$dir/post.out" -w '%{http_code}' -X POST "$base/api/external-annotations" \
      -H 'Content-Type: application/json' --data-binary "@$dir/annotations.json")
    [ "$code" = 201 ] && break
    sleep 0.5; i=$((i+1))
  done
  [ "$code" = 201 ] || { echo "could not load comments (HTTP $code): $(cat "$dir/post.out")" >&2; exit 2; }

  n=$(grep -o '"source":"draft"' "$dir/annotations.json" | wc -l | tr -d ' ')
  echo "url: $url"
  echo "loaded: $n comments"
  echo "result: $result"
  ;;
wait)
  result="${1:?usage: review_ui.sh wait <result-file> [--timeout s]}"; shift
  timeout=540
  [ "${1:-}" = "--timeout" ] && timeout="$2"
  i=0; while [ ! -f "$result" ] && [ $i -lt "$timeout" ]; do sleep 1; i=$((i+1)); done
  [ -f "$result" ] || { echo '{"decision":"pending"}'; exit 4; }
  cat "$result"; echo
  ;;
to-review)
  # Turn the user's final comments (decision message) back into review.txt, verbatim —
  # no model in between, so the user's edits are posted exactly as written.
  result="${1:?usage: review_ui.sh to-review <result.json> <out.txt> [--event COMMENT]}"; out="${2:?out file}"; shift 2
  event=COMMENT; [ "${1:-}" = "--event" ] && event="$2"
  command -v python3 >/dev/null || { echo "python3 needed to convert; convert the message by hand" >&2; exit 2; }
  python3 - "$result" "$out" "$event" <<'PY'
import json, re, sys
res = json.load(open(sys.argv[1])); out = sys.argv[2]; event = sys.argv[3]
if res.get("decision") not in ("annotated", "approved"):
    print(f"decision={res.get('decision')}: nothing to post"); sys.exit(5)
msg = res.get("message", "")
# drop the tool's trailing instructions to coding agents (not part of the review)
msg = re.split(r"\n\s*\n\s*\n\s*\n|\nTreat the findings above", msg)[0]
lines = msg.split("\n")
summary, comments, cur_file, cur = [], [], None, None
def flush():
    global cur
    if cur and "".join(cur["body"]).strip():
        comments.append(cur)
    cur = None
section = None
for ln in lines:
    m_file = re.match(r"^## (.+?)\s*$", ln)
    m_line = re.match(r"^### Lines? (\d+)(?:\s*-\s*(\d+))?", ln)
    if m_file:
        flush(); name = m_file.group(1)
        section = "general" if name.lower() in ("general", "general comments", "review") else "file"
        cur_file = None if section == "general" else name
        if section == "file": cur = {"path": cur_file, "line": 0, "body": []}
        continue
    if m_line and cur_file:
        flush(); cur = {"path": cur_file, "line": int(m_line.group(2) or m_line.group(1)), "body": []}; continue
    if ln.startswith("# ") or ln.startswith("**Diff:**"): continue
    if section == "general": summary.append(ln)
    elif cur is not None: cur["body"].append(ln)
flush()
if not comments and not "".join(summary).strip():
    print(f"decision={res.get('decision')} with no comments: ask the user what to post"); sys.exit(6)
def fix_body(body):
    t = "\n".join(body).strip()
    # "**Suggested code:**\n```\n...\n```" → GitHub suggestion block
    t = re.sub(r"\*\*Suggested code:\*\*\s*\n```[a-z]*\n(.*?)\n```", lambda m: "```suggestion\n" + m.group(1) + "\n```", t, flags=re.S)
    return t
with open(out, "w") as f:
    f.write(f"event: {event}\n=== summary\n{chr(10).join(summary).strip()}\n")
    for c in comments:
        f.write(f"=== comment {c['path']}:{c['line']} note\n{fix_body(c['body'])}\n")
print(f"wrote {out}: {len(comments)} comments, summary {'yes' if ''.join(summary).strip() else 'no'}")
PY
  ;;
posted)
  # Did the user post a review from Plannotator itself? Prints the URL of the user's latest
  # review on the PR submitted after the session started. exit 0 = found, 1 = none.
  repo="${1:?usage: review_ui.sh posted <owner/repo> <pr-number> <ui-dir>}"; num="${2:?pr number}"; dir="${3:?ui dir}"
  since=$(cat "$dir/started_at" 2>/dev/null) || { echo "no started_at in $dir" >&2; exit 2; }
  me=$(gh api user --jq .login) || exit 2
  url=$(gh api "repos/$repo/pulls/$num/reviews?per_page=100" \
        --jq "[.[] | select(.user.login == \"$me\" and .submitted_at >= \"$since\")] | last | .html_url // empty") || exit 2
  [ -n "$url" ] || exit 1
  echo "$url"
  ;;
*)
  sed -n '2,24p' "$0"; exit 2 ;;
esac
