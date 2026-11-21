#!/usr/bin/env python3
"""What do the framework's function calls cost? Cross-references the calls a run made (how many, at which call depth) with the cost of a call
measured by the ab-tests scenarios (calls-depth: marginal cost of the L-th nested call; calls-variants: cost of a `local` and of an argument).
Prints with the shared reporter (tools/benchmarks/reporting). Python standard library only.

  callmodel.py CALLS [--depth-run RUN] [--variants-run RUN] [--avg-args N] [--top N] [--save FILE]

  CALLS         a callcount.py run dir (calls.tsv: exact counts of a headless command), or a profiler report.json / run dir
                (attr.functions[].depths_by_group: calls per interaction from the xtrace pass)
  --depth-run   ab.sh run of scenarios/calls-depth.sh   (default: the latest one in runs/)
  --variants-run ab.sh run of scenarios/calls-variants.sh (default: the latest one in runs/; without it locals/args are not priced)

Model: a call at stack depth L costs marginal(L) = the extra time of the L-th layer in the calls-depth curve (piecewise linear, beyond the
deepest measured layer the last slope). LOW = Σ calls × marginal(depth). HIGH = LOW + calls × (locals declared by the function × cost of a local
+ avg args × cost of an arg). Locals come from a static scan of lib/ (a `local` that a path never reaches is still counted: HIGH is an upper bound).
"""
import argparse
import collections
import json
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))   # tools/benchmarks: the shared reporting package
sys.path.insert(0, HERE)

import ab_report                                                           # noqa: E402
from reporting import default_reporter as dr, term                          # noqa: E402
from reporting.term import c, pad, panel, bar, fmt_ms, fmt_num                # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
RUNS = os.path.join(HERE, "runs")
FUNC_DEF = re.compile(r"^(?:function\s+)?([A-Za-z_][\w.:@-]*)\s*(?:\(\))?\s*\{")
LOCAL_TOKEN = re.compile(r"^[A-Za-z_]\w*(=.*)?$")


# ── the cost of a call, from ab.sh runs ─────────────────────────────────────────────────────────────────────────────────────────────
def latest_run(name):
    """Newest ab.sh run dir whose scenario name is NAME, or None."""
    if not os.path.isdir(RUNS):
        return None
    best = None
    for d in sorted(os.listdir(RUNS)):
        p = os.path.join(RUNS, d)
        if os.path.isfile(os.path.join(p, "meta.txt")):
            try:
                if ab_report.load(p)[0].get("name") == name:
                    best = p
            except OSError:
                pass
    return best


def net_per_iteration(run_dir):
    """{side: microseconds per iteration over the control side} + {side: inner operations per iteration} of an ab.sh run."""
    meta, sides, samples = ab_report.load(run_dir)
    units, control = int(meta.get("units") or 0), meta.get("control") or ""
    if not units or control not in samples or not samples[control]:
        raise SystemExit(f"{run_dir}: needs AB_UNITS and AB_CONTROL (was it made by scenarios/calls-*.sh?)")
    med = {s: statistics.median(v) for s, v in samples.items() if v}
    net = {s: (med[s] - med[control]) / units for s in med}
    return net, meta.get("_per", {}), meta


def depth_curve(run_dir):
    """[(calls per iteration K, net µs per iteration)] sorted by K, starting at (0, 0): the cost of a chain of K nested calls."""
    net, per, _ = net_per_iteration(run_dir)
    pts = {0: 0.0}
    for s, n in per.items():
        if n and s in net:
            pts[int(n)] = net[s]
    if len(pts) < 3:
        raise SystemExit(f"{run_dir}: not a calls-depth run (needs several depths; AB_PER missing?)")
    return sorted(pts.items())


def marginal(curve, level):
    """Cost in µs of the LEVEL-th nested call (level >= 1): the slope of the curve's segment that contains it."""
    for (k0, c0), (k1, c1) in zip(curve, curve[1:]):
        if level <= k1:
            return (c1 - c0) / (k1 - k0)
    (k0, c0), (k1, c1) = curve[-2], curve[-1]
    return (c1 - c0) / (k1 - k0)


def variant_costs(run_dir):
    """(µs per `local` variable, µs per argument) from a calls-variants run; zeros when the run or its sides are missing."""
    if not run_dir:
        return 0.0, 0.0
    net, _, _ = net_per_iteration(run_dir)
    try:
        return max(0.0, (net["local3"] - net["call0"]) / 3), max(0.0, (net["call3args"] - net["call0"]) / 3)
    except KeyError:
        return 0.0, 0.0


def static_locals(repo=REPO, sub="lib"):
    """{function: number of variables its `local` statements declare}, scanned from the shell sources (indentation-agnostic, definitions at column 0)."""
    out, cur = {}, None
    for root, _, files in os.walk(os.path.join(repo, sub)):
        for fn in files:
            if not fn.endswith(".sh"):
                continue
            with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as f:
                for line in f:
                    m = FUNC_DEF.match(line)
                    if m:
                        cur = m.group(1)
                        out.setdefault(cur, 0)
                    elif cur and line.startswith("}"):
                        cur = None
                    elif cur:
                        s = line.strip()
                        if s.startswith("local ") or s.startswith("local\t"):
                            out[cur] += sum(1 for tok in s.split()[1:] if LOCAL_TOKEN.match(tok))
    return out


# ── the calls, from callcount.py or the profiler ────────────────────────────────────────────────────────────────────────────────────
def load_calls(path):
    """-> (calls, meta) with calls = {unit name: {function: {depth: count}}}. A unit is a marked section of a callcount run, or one profiler interaction."""
    if os.path.isdir(path) and os.path.isfile(os.path.join(path, "calls.tsv")):
        calls = collections.defaultdict(lambda: collections.defaultdict(dict))
        with open(os.path.join(path, "calls.tsv"), encoding="utf-8") as f:
            for line in f:
                sec, fn, depth, n = line.rstrip("\n").split("\t")
                calls[sec][fn][int(depth)] = int(n)
        meta = {}
        with open(os.path.join(path, "meta.txt"), encoding="utf-8") as f:
            for line in f:
                k, _, v = line.rstrip("\n").partition("\t")
                meta[k] = v
        meta["kind"] = "callcount"
        return calls, meta
    rp = os.path.join(path, "report.json") if os.path.isdir(path) else path
    with open(rp, encoding="utf-8") as f:
        rep = json.load(f)
    calls = collections.defaultdict(lambda: collections.defaultdict(dict))
    for fn in rep.get("attr", {}).get("functions", []):
        for gid, dd in (fn.get("depths_by_group") or {}).items():
            for depth, n in dd.items():
                calls[gid][fn["name"]][int(depth)] = n
    if not calls:
        raise SystemExit(f"{rp}: no call depths in this report: it predates the depth counting, run the profiler again (with the trace pass)")
    meta = {"kind": "profiler", "title": rep["meta"].get("title", "profiler run"), "latency": {g["id"]: g for g in rep["latency"]},
            "titles": {g["id"]: g["title"] for g in rep["latency"]}}
    return calls, meta


def estimate(fncalls, curve, locals_of, per_local, per_arg, avg_args):
    """{function: (calls, mean depth, low µs, high µs)} for one unit's {function: {depth: count}}."""
    out = {}
    for fn, dd in fncalls.items():
        n = sum(dd.values())
        if not n:
            continue
        low = sum(cnt * marginal(curve, max(1, d)) for d, cnt in dd.items())
        high = low + n * (locals_of.get(fn, 0) * per_local + avg_args * per_arg)
        out[fn] = (n, sum(d * cnt for d, cnt in dd.items()) / n, low, high)
    return out


# ── the report ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
def render(calls, meta, curve, per_local, per_arg, avg_args, locals_of, top=14, W=None, depth_run="", variants_run=""):
    """The cross-reference as lines for the terminal, made of the shared reporter's header and panels."""
    W = W or min(term.width(), 140)
    ests = {u: estimate(fn, curve, locals_of, per_local, per_arg, avg_args) for u, fn in calls.items()}
    rep = {"meta": {"title": "CALL COST MODEL", "commit": meta.get("git", "").replace("+dirty", ""), "branch": meta.get("name", meta.get("title", "")),
                    "dirty": meta.get("git", "").endswith("+dirty"), "rounds": 1, "duration_s": 0, "when": meta.get("stamp", "")}}
    out = dr.header(rep, W) + [""]
    cost_lines = [f"{c('cost of the L-th nested call (calls-depth)', 'dim')}   " + "  ".join(f"L{k}={c(ab_report.fmt_each(marginal(curve, k)), 'white')}" for k in (1, 2, 4, 8, 16)),
                  f"{c('a `local` variable', 'dim')} {c(ab_report.fmt_each(per_local), 'white')}   {c('an argument', 'dim')} {c(ab_report.fmt_each(per_arg), 'white')}   "
                  f"{c(f'assumed {avg_args:g} args per call', 'dim')}",
                  c(f"from {os.path.basename(depth_run)}" + (f" and {os.path.basename(variants_run)}" if variants_run else " (no calls-variants run: locals and args not priced)"), "faint")]
    out += panel("PRICE LIST", cost_lines, W, "cyan")
    baseline_ms = float(meta["baseline_ms"]) if meta.get("baseline_ms") else None

    if meta["kind"] == "callcount":
        total = collections.defaultdict(lambda: [0, 0.0, 0.0, 0.0])   # function -> calls, depth*calls, low, high
        for u, e in ests.items():
            for fn, (n, md, lo, hi) in e.items():
                t = total[fn]
                t[0] += n; t[1] += md * n; t[2] += lo; t[3] += hi
        calls_all = sum(t[0] for t in total.values())
        lo_all, hi_all = sum(t[2] for t in total.values()) / 1000, sum(t[3] for t in total.values()) / 1000
        lines = [f"{c(fmt_num(calls_all), 'white', bold=True)} calls counted   estimated call overhead "
                 f"{c(fmt_ms(lo_all), 'cyan', bold=True)} – {c(fmt_ms(hi_all), 'cyan', bold=True)}"]
        if baseline_ms:
            lines.append(f"of a {c(fmt_ms(baseline_ms), 'white')} run (uninstrumented): {c(f'{lo_all / baseline_ms * 100:.1f}% – {hi_all / baseline_ms * 100:.1f}%', 'yellow', bold=True)} "
                         f"of the time is spent on calling functions, not on what they do")
        else:
            lines.append(c("no baseline wall time (--no-baseline): shares not available", "dim"))
        out += [""] + panel("OVERHEAD", lines, W, "orange", "low = bare calls by depth · high = + locals and args")
        rows = sorted(total.items(), key=lambda kv: -kv[1][3])[:top]
        mx = rows[0][1][3] if rows else 1
        head = (pad(c("function", "dim"), 36) + pad(c("calls", "dim"), 9, "r") + pad(c("depth", "dim"), 7, "r") + pad(c("low", "dim"), 10, "r")
                + pad(c("high", "dim"), 10, "r") + pad(c("share", "dim"), 8, "r") + "  " + c("of high", "dim"))
        body = [head]
        for fn, (n, dsum, lo, hi) in rows:
            share = f"{hi / 1000 / baseline_ms * 100:.1f}%" if baseline_ms else ""
            body.append(pad(c(fn, "cyan"), 36) + pad(c(fmt_num(n), "white"), 9, "r") + pad(c(f"{dsum / n:.1f}", "dim"), 7, "r")
                        + pad(c(fmt_ms(lo / 1000), "dim"), 10, "r") + pad(c(fmt_ms(hi / 1000), "white", bold=True), 10, "r")
                        + pad(c(share, "yellow"), 8, "r") + "  " + bar(hi / mx, 18, "orange"))
        out += [""] + panel("WHERE THE CALL OVERHEAD GOES", body, W, "dim", f"top {len(rows)} of {len(total)} functions by high estimate")
        hist = collections.Counter()
        for fnd in calls.values():
            for dd in fnd.values():
                for d, n in dd.items():
                    hist[d] += n
        if hist:
            mxn = max(hist.values())
            dl = [f"{pad(c(f'depth {d}', 'dim'), 10)}{pad(c(fmt_num(hist[d]), 'white'), 9, 'r')}  {bar(hist[d] / mxn, 40, 'cyan')}" for d in sorted(hist)]
            out += [""] + panel("CALL DEPTH", dl, W, "teal", "calls by stack depth (1 = called from the top level)")
    else:   # profiler: one row per interaction
        lat, titles = meta["latency"], meta["titles"]
        head = (pad(c("interaction", "dim"), 36) + pad(c("calls", "dim"), 9, "r") + pad(c("depth", "dim"), 7, "r") + pad(c("low", "dim"), 10, "r")
                + pad(c("high", "dim"), 10, "r") + pad(c("latency", "dim"), 10, "r") + pad(c("share", "dim"), 14, "r"))
        body, rows = [head], []
        for u, e in ests.items():
            n = sum(v[0] for v in e.values())
            if not n:
                continue
            md = sum(v[1] * v[0] for v in e.values()) / n
            lo, hi = sum(v[2] for v in e.values()) / 1000, sum(v[3] for v in e.values()) / 1000
            val = (lat.get(u) or {}).get("value")
            rows.append((hi, u, n, md, lo, val))
        for hi, u, n, md, lo, val in sorted(rows, reverse=True)[:max(top, 20)]:
            share = f"{lo / val * 100:.1f}–{hi / val * 100:.1f}%" if val else ""
            body.append(pad(c(titles.get(u, u), "cyan"), 36) + pad(c(fmt_num(n), "white"), 9, "r") + pad(c(f"{md:.1f}", "dim"), 7, "r")
                        + pad(c(fmt_ms(lo), "dim"), 10, "r") + pad(c(fmt_ms(hi), "white", bold=True), 10, "r")
                        + pad(c(fmt_ms(val), "dim"), 10, "r") + pad(c(share, "yellow", bold=True), 14, "r"))
        out += [""] + panel("CALL OVERHEAD PER INTERACTION", body, W, "orange",
                            "calls per action from the xtrace pass (a lower bound: calls whose body prints no traced line are missed) · latency = the group's median")
    out += ["", c("estimates, not measurements: validate a finding by inlining the hot chain and A/B-ing it with ab.sh", "faint")]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("calls")
    ap.add_argument("--depth-run")
    ap.add_argument("--variants-run")
    ap.add_argument("--avg-args", type=float, default=2.0)
    ap.add_argument("--top", type=int, default=14)
    ap.add_argument("--save", metavar="FILE")
    ap.add_argument("--no-color", action="store_true")
    a = ap.parse_args()
    term.init(False if a.no_color else None)
    depth_run = a.depth_run or latest_run("call-depth")
    if not depth_run:
        raise SystemExit("no calls-depth run: ab.sh run scenarios/calls-depth.sh first (or pass --depth-run)")
    variants_run = a.variants_run or latest_run("call-variants")
    curve = depth_curve(depth_run)
    per_local, per_arg = variant_costs(variants_run)
    calls, meta = load_calls(a.calls)
    lines = render(calls, meta, curve, per_local, per_arg, a.avg_args, static_locals(), a.top, depth_run=depth_run, variants_run=variants_run or "")
    print("\n".join(lines))
    if a.save:
        term.set_color(False)
        lines = render(calls, meta, curve, per_local, per_arg, a.avg_args, static_locals(), a.top, depth_run=depth_run, variants_run=variants_run or "")
        with open(a.save, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
