#!/usr/bin/env python3
"""Grade keel-check eval runs.

Usage: grade.py <results_dir> [--scenarios evals/scenarios] [--md]

For each scenario, compares <results_dir>/<name>.json with scenarios/<name>/expected.json:
  - tier ok        the tier is one of the accepted tiers
  - found          required findings matched (file + regex on summary, at >= min severity)
  - missed         required findings not matched
  - false must     must-fix findings on clean scenarios, or must-fix that match nothing expected
  - noise          should-fix findings that match nothing expected (shown, not penalized hard)
"""
import json, re, sys, os, argparse

SEV = {"nit": 0, "should-fix": 1, "must-fix": 2}

def load(p):
    try:
        with open(p) as f: return json.load(f)
    except Exception as e:
        return {"_error": str(e)}

def matches(exp, f):
    base = exp["file"].split("/")[-1] if exp["file"] else ""
    if base and not f.get("_fixed") and not f.get("file", "").endswith(base):
        return False
    if base and f.get("_fixed") and base not in f.get("summary", ""):
        return False
    return re.search(exp["pattern"], f.get("summary", ""), re.I) is not None

def grade(name, exp, res):
    if "_error" in res:
        return {"name": name, "error": res["_error"]}
    findings = [f for f in res.get("findings", []) if f.get("severity") in SEV]
    # Problems keel fixed itself count as found at must-fix level (the skill fixes simple
    # must-fix items without asking). Fixed items never count as noise.
    for fx in res.get("fixed", []):
        text = fx if isinstance(fx, str) else json.dumps(fx)
        findings.append({"severity": "must-fix", "file": "", "summary": text, "_fixed": True})
    used = set(); found = []; missed = []; weak = []
    for e in exp["expect"]:
        hit = None
        for i, f in enumerate(findings):
            if i in used or not matches(e, f): continue
            hit = i; break
        if hit is None:
            if not e.get("optional"): missed.append(e["id"])
            continue
        used.add(hit)
        if SEV[findings[hit]["severity"]] >= SEV[e["min"]]: found.append(e["id"])
        elif not e.get("optional"): weak.append(e["id"])   # found but under-rated
        else: found.append(e["id"] + "(low)")
    extra = [f for i, f in enumerate(findings) if i not in used and not f.get("_fixed")]
    false_must = [f for f in extra if f["severity"] == "must-fix"]
    noise = [f for f in extra if f["severity"] == "should-fix"]
    required = [e for e in exp["expect"] if not e.get("optional")]
    return {
        "name": name,
        "tier": res.get("tier"), "tier_ok": res.get("tier") in exp["tier"], "tier_expected": exp["tier"],
        "required": len(required), "found": found, "missed": missed, "weak": weak,
        "false_must": false_must, "noise": noise,
        "tool_calls": res.get("tool_calls"), "fixed": res.get("fixed", []),
        "clean": exp.get("clean", False),
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results")
    ap.add_argument("--scenarios", default=os.path.join(os.path.dirname(__file__), "scenarios"))
    ap.add_argument("--md", action="store_true")
    a = ap.parse_args()
    rows = []
    for name in sorted(os.listdir(a.scenarios)):
        exp = load(os.path.join(a.scenarios, name, "expected.json"))
        path = os.path.join(a.results, name + ".json")
        if not os.path.exists(path):
            continue  # scenario not run in this batch
        res = load(path)
        rows.append(grade(name, exp, res))

    req = sum(r.get("required", 0) for r in rows)
    req_found = sum(r.get("required", 0) - len(r.get("missed", [])) - len(r.get("weak", [])) for r in rows if "error" not in r)
    tier_ok = sum(1 for r in rows if r.get("tier_ok"))
    fm = sum(len(r.get("false_must", [])) for r in rows)
    noise = sum(len(r.get("noise", [])) for r in rows)
    clean_rows = [r for r in rows if r.get("clean")]
    clean_ok = sum(1 for r in clean_rows if not r.get("false_must"))

    print(f"{'scenario':26} {'tier':10} {'req':>4} {'missed':18} {'false must':>10} {'noise':>5} {'calls':>5}")
    for r in rows:
        if "error" in r:
            print(f"{r['name']:26} ERROR {r['error']}"); continue
        t = (r['tier'] or '?') + ('' if r['tier_ok'] else '✗')
        m = ",".join(r['missed'] + [w + "(sev)" for w in r['weak']]) or "-"
        print(f"{r['name']:26} {t:10} {r['required']:>4} {m:18} {len(r['false_must']):>10} {len(r['noise']):>5} {str(r['tool_calls']):>5}")
    print("---")
    print(f"required findings caught at the right severity: {req_found}/{req}")
    print(f"tier correct: {tier_ok}/{len(rows)}")
    print(f"clean scenarios with no false must-fix: {clean_ok}/{len(clean_rows)}")
    print(f"false must-fix total: {fm}   unexpected should-fix (noise): {noise}")
    for r in rows:
        for f in r.get("false_must", []) + r.get("noise", []):
            print(f"  · {r['name']}: [{f['severity']}] {f.get('file')}:{f.get('line')} — {f.get('summary')}")

if __name__ == "__main__":
    main()
