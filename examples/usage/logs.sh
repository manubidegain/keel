#!/usr/bin/env bash
# keel usage source: access logs (nginx/Apache combined format, or JSON lines with method,
# path and user_agent fields). Calls, distinct clients and top user agents for a route.
#
#   usage:
#     sources:
#       logs: "bash .agents/usage/logs.sh /var/log/nginx/access.log"
#
# Pass one or more log files (gzipped is fine). Handles route targets only.
set -u
[ "${KEEL_TARGET_KIND:-}" = route ] || exit 0
[ $# -gt 0 ] || { echo "pass log files" >&2; exit 2; }
method="${KEEL_TARGET%% *}"; path="${KEEL_TARGET#* }"
[ "$method" = "$KEEL_TARGET" ] && { method=""; path="$KEEL_TARGET"; }
# route pattern → regex: escape dots, :param / {param} / [param] → one path segment
re=$(printf '%s' "$path" | sed -E 's/[.]/\\./g; s/:[A-Za-z0-9_]+|\{[^}]+\}|\[[^]]+\]/[^\/?" ]+/g')
for f in "$@"; do case "$f" in *.gz) gzip -dc "$f";; *) cat "$f";; esac; done 2>/dev/null | awk -v m="$method" -v re="^${re}([?\" ]|$)" '
  {
    if ($0 ~ /^[[:space:]]*\{/) {   # JSON lines
      meth=$0; sub(/.*"method"[[:space:]]*:[[:space:]]*"/,"",meth); sub(/".*/,"",meth)
      p=$0; sub(/.*"(path|url|uri)"[[:space:]]*:[[:space:]]*"/,"",p); sub(/".*/,"",p)
      ip=$0; if (sub(/.*"(ip|remote_addr|client_ip)"[[:space:]]*:[[:space:]]*"/,"",ip)) sub(/".*/,"",ip); else ip=""
      ua=$0; if (sub(/.*"(user_agent|ua|http_user_agent)"[[:space:]]*:[[:space:]]*"/,"",ua)) sub(/".*/,"",ua); else ua="unknown"
    } else {                        # combined: ip - - [date] "METHOD /path HTTP/1.1" status size "ref" "ua"
      ip=$1; n=split($0, q, "\""); split(q[2], r, " "); meth=r[1]; p=r[2]; ua=(n >= 6 ? q[6] : "unknown")
    }
    if (m != "" && meth != m) next
    if (p !~ re) next
    calls++; if (ip != "") ips[ip]=1; split(ua, u, " "); agents[u[1]]++
  }
  END {
    nip=0; for (i in ips) nip++
    top=""; for (k=0; k<3; k++) { best=""; bc=0; for (a in agents) if (agents[a] > bc) { best=a; bc=agents[a] }
      if (best == "") break; top = top (top ? ", " : "") best " " int(100*bc/calls) "%"; delete agents[best] }
    printf "{\"metric\":\"calls\",\"value\":%d,\"label\":\"calls in these logs\",\"detail\":\"%s\"}\n", calls, top
    if (nip) printf "{\"metric\":\"clients\",\"value\":%d,\"label\":\"distinct IPs\"}\n", nip
  }'
