"""Numbers every benchmark report needs: percentile, median, summary statistics, a rating against a budget, and the
"group" a reporter shows: one measured thing (samples in ms) with its details."""
import statistics

NOISY_CORES = 0.5   # other work above this many cores while a unit ran: its timings are inflated


def pct(vals, q):
    if not vals:
        return None
    s = sorted(vals)
    i = min(len(s) - 1, max(0, int(round(q / 100 * (len(s) - 1)))))
    return s[i]


def med(vals):
    return statistics.median(vals) if vals else None


def stats(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return {"n": len(vals), "min": min(vals), "med": med(vals), "p95": pct(vals, 95), "max": max(vals),
            "mean": sum(vals) / len(vals)}


def rate(value, budget):
    """good / ok / slow against a perceived-latency budget."""
    if value is None or not budget:
        return "na"
    r = value / budget
    return "good" if r <= 1 else "ok" if r <= 2 else "slow"


def group(gid, title, samples, budget_ms, kind="render", details=None, bytes_=None, **extra):
    """One scorecard row. SAMPLES are milliseconds per call; the headline is their median, rated against BUDGET_MS.
    DETAILS: [{"detail": name, "settle": median_ms, "p95": ms, "bytes": n, "forks": n, ...}] (one per case)."""
    st = stats(samples)
    value = st["med"] if st else None
    g = {"id": gid, "title": title, "kind": kind, "budget_ms": budget_ms, "n": len(samples), "metric": "settle", "settle": st,
         "value": value, "rating": rate(value, budget_ms), "samples": list(samples), "details": details or []}
    if bytes_ is not None:
        g["bytes"] = stats(bytes_)
    g.update(extra)
    return g


def compare_groups(groups, base):
    """Per-group delta of the headline value against an earlier report (its dict): the rows of the report's compare block."""
    old = {g["id"]: g for g in base.get("latency", [])}
    rows = []
    for g in groups:
        o = old.get(g["id"])
        if not o or o.get("value") is None or g.get("value") is None:
            continue
        rows.append({"id": g["id"], "title": g["title"], "old": o["value"], "new": g["value"],
                     "delta_pct": (g["value"] - o["value"]) / o["value"] * 100 if o["value"] else 0.0})
    return {"when": base.get("meta", {}).get("when"), "commit": base.get("meta", {}).get("commit"), "rows": rows,
            "old_noise": None, "new_noise": None}
