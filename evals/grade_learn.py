#!/usr/bin/env python3
"""Grade keel-learn runs: grade_learn.py <out_dir> <repos_dir> [learn_dir]."""
import json, os, re, subprocess, sys
out, repos = sys.argv[1], sys.argv[2]
learn = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(__file__), "learn")
ok = total = 0
for name in sorted(os.listdir(learn)):
    exp = json.load(open(os.path.join(learn, name, "expected.json")))
    p = os.path.join(out, name + ".json")
    if not os.path.exists(p):
        print(f"{name}: no result"); continue
    res = json.load(open(p)); msg = open(os.path.join(out, name + ".md")).read()
    problems = []
    if exp["culprit_subject"] not in res.get("culprit", {}).get("subject", ""):
        problems.append(f"culprit {res.get('culprit')}")
    if not any(w in res.get("why", "").lower() for w in exp["why_any"]):
        problems.append(f"why {res.get('why')!r}")
    for need in exp["proposals_need"]:
        if not any(re.search(need["pattern"], pr.get(need["where"], ""), re.I) for pr in res.get("proposals", [])):
            problems.append(f"no {need['id']} proposal")
    for a in exp["must_not_name_authors"]:
        if re.search(rf"\b{a}\b", msg, re.I): problems.append(f"names author {a}")
    status = subprocess.run(["git", "status", "--porcelain"], cwd=os.path.join(repos, name), capture_output=True, text=True).stdout
    for w in exp["must_not_write"]:
        if w in status: problems.append(f"wrote {w} without approval")
    total += 1; ok += not problems
    print(f"{'PASS' if not problems else 'FAIL'} {name}: culprit={res.get('culprit',{}).get('subject')!r} why={res.get('why')!r} proposals={len(res.get('proposals',[]))} calls={res.get('tool_calls')}" + ("" if not problems else "  — " + "; ".join(problems)))
print(f"--- {ok}/{total} passed")
