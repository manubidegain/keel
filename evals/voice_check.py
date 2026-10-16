#!/usr/bin/env python3
"""Flag assistant tells in a keel-review review.txt (what would be posted).

Usage: voice_check.py <review.txt> [...]
Exit 1 if any hard tell is found. Soft tells are listed for a human to judge.
"""
import re, sys

HARD = [
    (r"\b(keel|claude|anthropic|chatgpt|copilot)\b", "names a tool/AI"),
    (r"\bAI\b|\bIA\b|inteligencia artificial|automated review|revisi[oó]n autom[aá]tica|as an ai", "mentions AI/automation"),
    (r"<!--", "hidden marker"),
    (r"generated with|reviewed by|co-authored-by|generado (con|por)", "attribution"),
    (r"\bmust-fix\b|\bshould-fix\b", "internal severity jargon"),
]
SOFT = [
    (r"great (job|work|question)|nice work|buen trabajo|excelente trabajo|gran trabajo", "praise filler"),
    (r"i hope this helps|let me know if|espero que (esto )?(te )?sirva|cualquier (duda|cosa) avis", "assistant closing"),
    (r"it'?s worth noting|cabe (destacar|mencionar|se[nñ]alar)|vale la pena (mencionar|destacar)", "assistant hedge"),
    (r"overall,|en general, (este|el) pr|in summary|en resumen", "summary boilerplate"),
    (r"here'?s (a|the) (breakdown|summary)|a continuaci[oó]n", "breakdown framing"),
    (r"^#{1,6} ", "markdown heading"),
    (r"—", "em dash"),
    (r"[✅❌⚠️🚀🔴🟡🟢💡📝]", "emoji bullet"),
    (r"\*\*[^*]+\*\*", "bold"),
]

def check(path):
    text = open(path, encoding="utf-8").read()
    # only what gets posted: drop the event line and the === headers
    body = "\n".join(l for l in text.splitlines() if not l.startswith(("event:", "=== ")))
    hard = [(why, m.group(0)) for pat, why in HARD for m in re.finditer(pat, body, re.I | re.M)]
    soft = {}
    for pat, why in SOFT:
        n = len(re.findall(pat, body, re.I | re.M))
        if n: soft[why] = n
    comments = text.count("=== comment")
    words = len(body.split())
    print(f"{path}: {comments} inline comments, {words} words")
    for why, s in hard: print(f"  HARD  {why}: {s!r}")
    for why, n in soft.items(): print(f"  soft  {why} ×{n}")
    return not hard

ok = all([check(p) for p in sys.argv[1:]])
sys.exit(0 if ok else 1)
