#!/usr/bin/env python3
"""Grade keel-plan runs: grade_plan.py <out_dir> [plans_dir]. Reads <out>/<scenario>.json."""
import json, os, re, sys
out = sys.argv[1]
plans = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "plans")
rank = {"question": 0, "should": 1, "must": 2}
total = ok = 0
for name in sorted(os.listdir(plans)):
    exp = json.load(open(os.path.join(plans, name, "expected.json")))
    path = os.path.join(out, name + ".json")
    if not os.path.exists(path):
        print(f"{name}: no result"); continue
    res = json.load(open(path)); notes = res.get("notes", [])
    problems = []
    if res.get("tier") not in exp["tier"]:
        problems.append(f"tier {res.get('tier')} (expected {'/'.join(exp['tier'])})")
    for e in exp["expect"]:
        rx = re.compile(e["pattern"], re.I | re.S)
        hits = [n for n in notes if rx.search(n.get("quote", "") + " " + n.get("text", ""))]
        best = max((rank.get(n.get("severity"), 0) for n in hits), default=-1)
        need = rank.get(e["min"], 0) if e["min"] != "any" else 0
        if best < 0: problems.append(f"missed {e['id']}")
        elif best < need: problems.append(f"{e['id']} too low ({[k for k,v in rank.items() if v==best][0]} < {e['min']})")
    musts = sum(1 for n in notes if n.get("severity") == "must")
    if "max_must" in exp and musts > exp["max_must"]: problems.append(f"{musts} must (max {exp['max_must']})")
    if "max_notes" in exp and len(notes) > exp["max_notes"]: problems.append(f"{len(notes)} notes (max {exp['max_notes']})")
    total += 1; ok += not problems
    print(f"{'PASS' if not problems else 'FAIL'} {name}: tier={res.get('tier')} notes={len(notes)} must={musts} calls={res.get('tool_calls')}" + ("" if not problems else "  — " + "; ".join(problems)))
print(f"--- {ok}/{total} passed")
