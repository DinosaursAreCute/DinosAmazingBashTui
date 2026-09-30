"""Rule-based findings. Each one states the symptom, the evidence and where to look."""
from .analyze import LAYERS


def _fmt_ms(v):
    return f"{v:.0f} ms" if v >= 10 else f"{v:.1f} ms"


def _top_layer(attr, gid, kind="w"):
    v = attr["groups"].get(gid, {}).get(kind)
    if not v or not v["layers"]:
        return None
    layer, ms = max(v["layers"].items(), key=lambda kv: kv[1])
    return layer, ms, ms / max(v["total_ms"], 1e-9)


def _top_self(attr, gid, kind="w", n=3):
    v = attr["groups"].get(gid, {}).get(kind)
    if not v:
        return []
    items = sorted(v["self"].items(), key=lambda kv: -kv[1])[:n]
    return [(f, ms) for f, ms in items]


SKIP_FRAMES = {"main", "source", "⟨main⟩", "tui.start_cached", "tui.run"}


def short_path(path, n=6):
    """Hot path without the frames every scenario shares."""
    names = [p[0] for p in (path or [])]
    while names and names[0] in SKIP_FRAMES:
        names.pop(0)
    return " › ".join(names[:n])


def generate(rep):
    lat = {g["id"]: g for g in rep["latency"]}
    attr = rep["attr"]
    out = []

    def add(sev, title, detail, where="", group=""):
        out.append({"sev": sev, "title": title, "detail": detail, "where": where, "group": group})

    # 1. idle churn
    idle = lat.get("idle", {}).get("idle")
    if idle and idle["frames_per_s"] >= 2:
        v = attr["groups"].get("idle", {}).get("a")
        top = []
        if v:
            skip = SKIP_FRAMES | {"_tui_api._tick"}
            top = [(f, ms) for f, ms in sorted(v["incl"].items(), key=lambda kv: -kv[1]) if f not in skip and not f.startswith("⟨")][:3]
        ev = ""
        if top:
            ev = " Ambient work is dominated by " + ", ".join(f"{f} ({_fmt_ms(ms)}/3 s)" for f, ms in top) + "."
        procs = v["layers"].get("process", 0.0) / max(v["total_ms"], 1e-9) if v else 0
        if procs > 0.2:
            ev += f" {procs * 100:.0f}% of it is forks and external programs."
        add("crit" if idle["frames_per_s"] >= 10 else "warn",
            f"Idle app repaints {idle['frames_per_s']:.0f} frames/s",
            f"With nothing happening the app still writes {idle['bytes_per_s'] / 1024:.1f} KB/s to the terminal and "
            f"uses {idle['cpu_pct']:.1f}% of a core." + ev,
            ", ".join(f for f, _ in top), "idle")

    # 2. forks / external commands on user paths
    by_group_forks = {}
    for f in attr["forks"]:
        for gid, c in f["groups"].items():
            by_group_forks.setdefault(gid, []).append((c, f))
    inp = []   # input-path groups that spawn processes
    for gid, items in by_group_forks.items():
        g = lat.get(gid)
        if not g:
            continue
        total = sum(c for c, _ in items)
        n_ex = sum(e["groups"].get(gid, 0) for e in attr["execs"])
        ex_ms = sum(e["ms"] * (e["groups"].get(gid, 0) / max(e["count"], 1e-9)) for e in attr["execs"] if gid in e["groups"])
        top = max(items, key=lambda x: x[0])[1] if items else None
        site = f"{top['func']} ({top['src']})" if top else ""
        if g["kind"] == "input" and total + n_ex >= 0.5:
            inp.append((g, total, n_ex, site))
        elif g["kind"] in ("nav", "resize") and total + n_ex >= 5:
            add("warn", f"{g['title']}: {total:.0f} forks + {n_ex:.0f} external programs per action (~{_fmt_ms(ex_ms)} in programs)",
                "Processes spawned while switching pages or resizing; each one is wall-clock the user waits for.", site, gid)
    if inp:
        inp.sort(key=lambda x: -(x[1] + x[2]))
        sites = {}
        for _, _, _, s in inp:
            sites[s] = sites.get(s, 0) + 1
        main_site = max(sites, key=sites.get)
        detail = "; ".join(f"{g['title']}: {t:.1f} forks + {e:.1f} programs" for g, t, e, _ in inp[:5])
        add("crit", f"Input handling spawns processes on {len(inp)} interaction types",
            "Hover, focus and click should be fork-free (a fork costs ~1 ms, an awk ~4 ms). " + detail + ".", main_site,
            inp[0][0]["id"])

    # 3. external programs ranked
    if attr["execs"]:
        e = attr["execs"][0]
        if e["ms"] >= 5:
            add("warn", f"`{e['cmd']}` is the most expensive external program ({e['count']:.0f} runs, {_fmt_ms(e['ms'])} per scenario pass)",
                "Runs spawned from " + e["caller"] + "; scenarios: " + ", ".join(sorted(e["groups"])[:5]) + ".",
                e["caller"])

    # 4. budget breaches with attribution
    for g in rep["latency"]:
        if g["rating"] in ("ok", "slow") and g["id"] != "idle":
            tl = _top_layer(attr, g["id"])
            path = rep["paths"].get(g["id"])
            where = short_path(path)
            body = f"{g['title']} takes {_fmt_ms(g['value'])} (budget {_fmt_ms(g['budget_ms'])}, {g['value'] / g['budget_ms']:.1f}×)."
            if tl:
                body += f" {tl[2] * 100:.0f}% of it runs in {LAYERS[tl[0]][0]}."
            add("crit" if g["rating"] == "slow" else "warn", f"{g['title']} is over budget", body, where, g["id"])

    # 5. a key binding that does nothing
    kg = lat.get("nav.key")
    if kg and kg.get("went_false"):   # noqa
        add("warn", "alt+2 does not switch pages on a warm start",
            "The demo binds alt+1..0 in _nav.xml, but the key is dispatched with no binding found "
            "(handled in <1 ms, no page change). Mouse navigation works.", "share/demo/_nav.xml", "nav.key")

    # 6. amplification: functions called very often per action on input paths
    for f in attr["functions"][:80]:
        for gid, ms in f["groups"].items():
            g = lat.get(gid)
            if g and g["kind"] == "input" and f["calls"] >= 300 and ms >= 1.0:
                add("info", f"{f['name']} runs {f['calls']:.0f}× per {g['title'].lower()} action",
                    f"{_fmt_ms(ms)} self time per action. Check for a loop that should be batched or cached.",
                    f"{f['name']} ({f['file']})", gid)
                break

    # 7. output volume
    for gid, limit, what in (("hover.move", 400, "hover"), ("focus.next", 1500, "focus move")):
        g = lat.get(gid)
        if g and g.get("bytes") and g["bytes"]["med"] and g["bytes"]["med"] > limit:
            add("info", f"A {what} writes {g['bytes']['med']:.0f} bytes to the terminal",
                "Redraw only the affected cells; large writes cost latency over SSH and in slow terminals.", "", gid)

    # 8. startup
    cold, warm = rep["startup"].get("cold"), rep["startup"].get("warm")
    if warm:
        big = max(warm["spans"], key=lambda s: s["end"] - s["start"]) if warm["spans"] else None
        if warm["ready_ms"] > 700 and big:
            add("warn", f"Warm start takes {_fmt_ms(warm['ready_ms'])}",
                f"Largest phase: {big['label']} ({_fmt_ms(big['end'] - big['start'])}).", big["label"], "startup.warm")
    if cold and warm:
        add("info", f"Cold start is {cold['ready_ms'] / warm['ready_ms']:.1f}× slower than warm",
            f"{_fmt_ms(cold['ready_ms'])} vs {_fmt_ms(warm['ready_ms'])}; the difference is the page-cache build behind the splash.",
            "", "startup.cold")

    # 9. dominant layers overall
    tot = {}
    for gid, gv in attr["groups"].items():
        w = gv.get("w")
        if w and not gid.startswith("startup") and gid != "idle":
            for ly, ms in w["layers"].items():
                tot[ly] = tot.get(ly, 0.0) + ms
    s = sum(tot.values())
    if s:
        ly, ms = max(tot.items(), key=lambda kv: kv[1])
        add("info", f"{LAYERS[ly][0]} is where interaction time goes ({ms / s * 100:.0f}%)", LAYERS[ly][1] + ".", "", "")
        proc = tot.get("process", 0.0) / s
        if proc >= 0.15:
            add("warn", f"{proc * 100:.0f}% of interaction time is forks and external programs",
                "Bash builtins and parameter expansion do the same jobs without a process.", "", "")

    # logging / perf counters that run while disabled
    tot_d = sum(w["layers"].get("diag", 0.0) for gid, gv in attr["groups"].items() for k, w in gv.items()
                if k == "w" and not gid.startswith("startup"))
    tot_all = sum(w["total_ms"] for gid, gv in attr["groups"].items() for k, w in gv.items()
                  if k == "w" and not gid.startswith("startup"))
    if tot_all and tot_d / tot_all >= 0.03:
        add("warn", f"Logging and perf counters take {tot_d / tot_all * 100:.0f}% of interaction time",
            "tui.log / _tui_perf.* are called on hot paths even with logging and tracking off; guard them at the call site "
            "or make them a single `(( ))` test.", "tui.log", "")

    cal = rep.get("calibration")
    if cal and cal.get("mae_pct") is not None and cal["mae_pct"] > 25:
        add("warn", f"Trace calibration is loose: {cal['mae_pct']:.0f}% mean error ({cal['bias_pct']:+.0f}% bias)",
            "Rescaled trace times disagree with the untraced probe times for the same functions; treat per-function "
            "numbers as relative, and see the calibration check in the deep dive.", "", "")

    # 10. good news
    fast = [g["title"] for g in rep["latency"] if g["rating"] == "good" and g["kind"] in ("input", "nav")]
    if fast:
        add("good", f"{len(fast)} interaction types are within budget", ", ".join(fast[:6]) + (" …" if len(fast) > 6 else ""))

    # 11. run quality
    for w in rep.get("warnings", []):
        add("warn", "Profiler warning", w)
    order = {"crit": 0, "warn": 1, "info": 2, "good": 3}
    out.sort(key=lambda i: order[i["sev"]])
    return out
