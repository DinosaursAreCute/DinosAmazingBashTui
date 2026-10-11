#!/usr/bin/env python3
"""Keeps the explorer's data current: for every run in reports/ it writes report.js (the run, loadable from a file:// page)
and reports/index.js (a small summary of all runs). Idempotent and cheap: only new or changed runs are converted.
profile.py calls update() after each run; run this file yourself to catch up (or just `explorer.sh`)."""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dprof.analyze import noise  # noqa: E402
REPORTS = os.path.join(HERE, "reports")


def _summary(rid, d):
    meta = d.get("meta", {})
    groups = {}
    for g in d.get("latency", []):
        groups[g["id"]] = [g.get("value"), g.get("rating"), g.get("n"), g.get("budget_ms"), g.get("failed", 0)]
    st = d.get("startup", {})
    ins = {}
    for i in d.get("insights", []):
        ins[i.get("sev")] = ins.get(i.get("sev"), 0) + 1
    m = d.get("machine") or meta.get("machine") or {}
    return {
        "id": rid, "meta": {k: v for k, v in meta.items() if k not in ("machine", "warnings")},
        "machine": {k: m.get(k) for k in ("id", "cpu_model", "logical_cpus", "physical_cores", "ram_gb", "kernel", "distro", "virtualization")} if m else None,
        "warnings": len(d.get("warnings") or []), "insights": ins, "groups": groups,
        "startup": {k: (v or {}).get("ready_ms") for k, v in st.items()},
        "noise": noise(d.get("resources")),
        "traced": bool(d.get("attr", {}).get("groups")), "has_setup": bool(d.get("setup")), "has_resources": bool(d.get("resources")),
    }


def update(reports=REPORTS, quiet=True):
    """Returns the number of runs indexed."""
    index = []
    for path in sorted(glob.glob(os.path.join(reports, "*", "report.json"))):
        rdir = os.path.dirname(path)
        rid = os.path.basename(rdir)
        if os.path.islink(rdir):   # `latest`
            continue
        js = os.path.join(rdir, "report.js")
        try:
            with open(path) as f:
                raw = f.read()
            d = json.loads(raw)
        except (OSError, ValueError) as e:
            if not quiet:
                print(f"skip {rid}: {e}", file=sys.stderr)
            continue
        if not os.path.exists(js) or os.path.getmtime(js) < os.path.getmtime(path):
            with open(js, "w") as f:
                f.write("DPROF.run(%s,%s);\n" % (json.dumps(rid), raw.strip()))
        index.append(_summary(rid, d))
    with open(os.path.join(reports, "index.js"), "w") as f:
        f.write("window.DPROF_INDEX=%s;\n" % json.dumps(index, separators=(",", ":")))
    return len(index)


if __name__ == "__main__":
    n = update(quiet=False)
    print(f"explorer data: {n} runs indexed; open {os.path.join(HERE, 'explorer', 'index.html')}")
