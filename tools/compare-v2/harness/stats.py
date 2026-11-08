"""Statistics. Unit of independence is the ROUND (a fresh process, fresh HOME): samples inside a round share warm caches,
so each round is reduced to its median first, and every spread/CI/comparison is computed across rounds.

No outlier is ever dropped; outliers are only flagged (modified z-score > 3.5). Comparisons use a percentile bootstrap of the
ratio of medians (lower is better for every metric here); a difference counts only if the CI excludes 1, the effect is larger
than MIN_EFFECT, and the absolute gap is above the metric's noise floor."""
import math
import random
import statistics

# key -> (label, unit, decimals, abs noise floor for 'tie')
METRICS = {
    "ready_ms": ("ready", "ms", 1, 0.5), "settled_ms": ("done", "ms", 1, 0.5),
    "first_paint_ms": ("first paint", "ms", 1, 0.5), "first_byte_ms": ("first byte", "ms", 1, 0.5),
    "cpu_ms": ("CPU", "ms", 0, 2.0), "bytes": ("written", "B", 0, 16), "paints": ("paints", "", 0, 0.5),
    "cpu_pct": ("idle CPU", "%", 2, 0.05), "wakeups_s": ("wakeups", "/s", 1, 0.5), "bytes_s": ("idle bytes", "B/s", 0, 8),
    "pss_kb": ("PSS", "kB", 0, 256), "rss_kb": ("RSS", "kB", 0, 256), "procs": ("procs", "", 0, 0.5), "threads": ("threads", "", 0, 0.5),
}
KIND_METRICS = {
    "latency": ["settled_ms", "ready_ms", "first_paint_ms", "first_byte_ms", "cpu_ms", "bytes", "paints"],
    "idle": ["cpu_pct", "wakeups_s", "bytes_s"],
    "memory": ["pss_kb", "rss_kb", "procs", "threads"],
}
PRIMARY = {"latency": "settled_ms", "idle": "cpu_pct", "memory": "pss_kb"}
MIN_EFFECT = 0.05
B = 2000


def quantile(xs, q):
    xs = sorted(xs)
    if not xs:
        return None
    k = (len(xs) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def summarize(vals, rng):
    """Spread statistics of per-round values (plus a bootstrap CI of the median)."""
    n = len(vals)
    if not n:
        return None
    med = statistics.median(vals)
    mad = statistics.median(abs(v - med) for v in vals)
    boots = sorted(statistics.median(rng.choices(vals, k=n)) for _ in range(B // 2)) if n > 1 else [med, med]
    return {"n": n, "min": min(vals), "max": max(vals), "median": med, "mean": statistics.fmean(vals),
            "sd": statistics.stdev(vals) if n > 1 else 0.0, "p25": quantile(vals, .25), "p75": quantile(vals, .75),
            "mad": mad, "cv": (statistics.stdev(vals) / statistics.fmean(vals)) if n > 1 and statistics.fmean(vals) else 0.0,
            "ci": [boots[int(.025 * len(boots))], boots[min(len(boots) - 1, int(.975 * len(boots)))]],
            "outliers": sum(1 for v in vals if n >= 5 and mad and abs(v - med) > 0.05 * abs(med) and abs(0.6745 * (v - med) / mad) > 3.5)}


def compare(a, b, metric, rng):
    """b relative to a (ratio < 1: b is lower = better). Returns ratio, CI, verdict in {'a','b','tie','unclear'} ('a' = a is better)."""
    if not a or not b:
        return None
    ma, mb = statistics.median(a), statistics.median(b)
    floor = METRICS[metric][3]
    out = {"ratio": mb / ma if ma else None, "delta": mb - ma, "ci": None, "verdict": "tie"}
    if abs(mb - ma) < floor:
        return out
    if len(a) < 2 or len(b) < 2 or not ma:
        out["verdict"] = "unclear"
        return out
    rs = []
    for _ in range(B):
        x = statistics.median(rng.choices(a, k=len(a)))
        if x:
            rs.append(statistics.median(rng.choices(b, k=len(b))) / x)
    rs.sort()
    lo, hi = rs[int(.025 * len(rs))], rs[min(len(rs) - 1, int(.975 * len(rs)))]
    out["ci"] = [lo, hi]
    if lo > 1 and mb / ma > 1 + MIN_EFFECT:
        out["verdict"] = "a"
    elif hi < 1 and mb / ma < 1 - MIN_EFFECT:
        out["verdict"] = "b"
    else:
        out["verdict"] = "tie" if abs(mb / ma - 1) <= MIN_EFFECT else "unclear"
    return out


def per_round(samples, metric):
    """Median of the ok samples of each round -> list of per-round values."""
    by = {}
    for s in samples:
        if s.get("ok") and s.get(metric) is not None:
            by.setdefault(s["round"], []).append(s[metric])
    return [statistics.median(v) for _, v in sorted(by.items())]


def analyze(results, seed=1):
    """results = the run JSON. Returns {'apps','steps':[...],'score':{...}} ready for the reports."""
    rng = random.Random(seed)
    apps = [a["name"] for a in results["meta"]["apps"]]
    base = apps[0]
    steps = []
    for st in results["steps"]:
        name, kind = st["name"], st["kind"]
        row = {"name": name, "kind": kind, "apps": {}, "cmp": {}}
        for a in apps:
            samples = results["data"].get(a, {}).get(name, [])
            rounds = {s["round"] for s in samples}
            okr = {s["round"] for s in samples if s.get("ok")}
            m = {}
            for k in KIND_METRICS[kind]:
                vals = per_round(samples, k)
                m[k] = {"vals": vals, "sum": summarize(vals, rng)}
            row["apps"][a] = {"metrics": m, "ok": [len(okr), len(rounds)], "samples": len(samples),
                              "stale": any(s.get("stale") for s in samples)}
        for a in apps[1:]:
            row["cmp"][a] = {k: compare(row["apps"][base]["metrics"][k]["vals"], row["apps"][a]["metrics"][k]["vals"], k, rng)
                             for k in KIND_METRICS[kind]}
        steps.append(row)
    score = {}
    for a in apps[1:]:
        ratios, win, loss, tie = [], 0, 0, 0
        for r in steps:
            c = (r["cmp"][a].get(PRIMARY[r["kind"]]) if r["kind"] == "latency" and not r["name"].startswith("startup") else None)
            if not c:
                continue
            if c["ratio"]:
                ratios.append(c["ratio"])
            win += c["verdict"] == "a"
            loss += c["verdict"] == "b"
            tie += c["verdict"] in ("tie", "unclear")
        score[a] = {"geomean": math.exp(statistics.fmean(math.log(r) for r in ratios)) if ratios else None,
                    "base_better": win, "other_better": loss, "tie": tie, "n": len(ratios)}
    return {"apps": apps, "base": base, "steps": steps, "score": score}
