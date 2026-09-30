"""Turns raw runs (latency rounds + traces) into the report model both renderers consume.

Everything here is pure data in, plain dict/list/number out (JSON-serialisable), so a saved
report.json can be re-rendered later or diffed against another run.
"""
import os
import re
import statistics

from .scenarios import GROUP_INFO

# layer -> (title, what it is)
LAYERS = {
    "input": ("Input", "key/mouse decoding, bindings, coalescing"),
    "loop": ("Main loop", "tui.run, ticks, timers, hooks"),
    "focus": ("Focus & hover", "focus ring, hover tracking, hit tests"),
    "scroll": ("Scrolling", "pane scrolling and queued redraws"),
    "markup": ("Markup", "parse, validate, build the widget tree"),
    "cache": ("Page cache", "snapshot load/validate/save"),
    "style": ("Style", "CSS classes, themes, SGR"),
    "layout": ("Layout", "pane/widget geometry"),
    "render": ("Render", "drawing panes/widgets into frames"),
    "flush": ("Flush", "frame composition and terminal writes"),
    "widgets": ("Widgets", "widget behaviour and text measuring"),
    "chrome": ("Chrome", "footer, dialogs, palette, modals"),
    "term": ("Terminal", "terminal control sequences and queries"),
    "plugin": ("Plugins", "plugin + hook machinery"),
    "config": ("Config", "settings and keybind persistence"),
    "core": ("Core", "state, API, registry, misc helpers"),
    "app": ("App code", "page callbacks of the profiled app"),
    "diag": ("Logging & perf", "tui.log and perf counters that run even when off"),
    "process": ("Subprocesses", "forks and external programs"),
}
LAYER_ORDER = list(LAYERS)

FILE_LAYER = {
    "tui_input.sh": "input", "tui_markup.sh": "markup", "tui_parse.sh": "markup", "tui_build.sh": "markup",
    "tui_node.sh": "markup", "tui_validate.sh": "markup", "tui_validate_rules.sh": "markup",
    "tui_cache.sh": "cache", "tui_style.sh": "style", "colors.sh": "style", "tui_layout.sh": "layout",
    "tui_canvas.sh": "render", "tui_paint.sh": "render", "tui_emit.sh": "flush", "terminal_renderer.sh": "render",
    "tui_widgets.sh": "widgets", "tui_text.sh": "widgets", "tui_cmd.sh": "chrome", "tui_dialog.sh": "chrome",
    "tui_footer.sh": "chrome", "tui_modal.sh": "chrome", "terminal_controls.sh": "term",
    "tui_plugin.sh": "plugin", "tui_config.sh": "config", "state.sh": "core", "tui_api.sh": "core",
    "tui_registry.sh": "core", "tui_home.sh": "core", "perf.sh": "core", "tui.sh": "core", "app.sh": "loop",
    "probe_shim.sh": "core",
}
# tui.sh and friends mix many jobs: their functions are classified by name instead
FUNC_RULES = [
    (r"^tui\.log|_tui_perf|^tui\.perf", "diag"),
    (r"pane_content_need|inset|eff_border|content_rect|too_small|content_fit|calc_bounds|collect_leaves|pane_at", "layout"),
    (r"fill_pane|repeat_|align_pad", "render"),
    (r"clock|_now|_ms$|job_|^tui\.exec", "loop"),
    (r"banner|_tr_", "widgets"),
    (r"layout|relayout|apply_resize|root_h", "layout"),
    (r"flush|_emit|emit_|frame", "flush"),
    (r"draw|render|paint|redraw|canvas", "render"),
    (r"scroll", "scroll"),
    (r"focus|hover|locate|hit", "focus"),
    (r"mouse|key_|_key|input|escape|coalesce|dispatch|next_byte|bind", "input"),
    (r"style|sgr|class|theme|css|color", "style"),
    (r"cache", "cache"),
    (r"parse|build|markup|validate|load|factory", "markup"),
    (r"^tui\.run$|tick|hook|^main$|⟨main⟩|start", "loop"),
    (r"footer|palette|modal|dialog|overlay|notif", "chrome"),
    (r"widget|text|label|button|tabs|table", "widgets"),
]
_FUNC_RULES = [(re.compile(p), l) for p, l in FUNC_RULES]
_MIXED = {"tui.sh", "terminal_renderer.sh", "tui_api.sh", "state.sh", "tui_registry.sh"}
APP_FILE = re.compile(r"_callbacks\.sh$|^demo|^debug_|_header\.sh$|_tabs\.sh$|_init\.sh$")


def layer_of(func, file):
    if func.startswith("⟨"):
        return "process"
    if file and APP_FILE.search(file):
        return "app"
    base = FILE_LAYER.get(file or "", None)
    if base is None:
        base = "core" if (file or "").endswith(".sh") else "core"
        if file and ("plugin" in file):
            base = "plugin"
    if file in _MIXED or base == "core":
        low = func.lower()
        for rx, layer in _FUNC_RULES:
            if rx.search(low):
                return layer
        return base if file not in _MIXED else "core"
    return base


# ── small stats helpers ──────────────────────────────────────────────────────
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


# ── latency ──────────────────────────────────────────────────────────────────
def latency_groups(rounds):
    by = {}
    for r in rounds:
        for a in r["actions"]:
            by.setdefault(a["group"], []).append(a)
    groups = []
    order = list(GROUP_INFO)
    for gid in order:
        if gid.startswith("startup"):
            which = gid.split(".")[1]
            vals = [r["startup"][which]["ready_ms"] for r in rounds if which in r["startup"] and r["startup"][which].get("ready_ms")]
            if not vals:
                continue
            title, kind, budget = GROUP_INFO[gid]
            tls = [r["startup"][which] for r in rounds if which in r["startup"]]
            groups.append({
                "id": gid, "title": title, "kind": kind, "budget_ms": budget, "n": len(vals),
                "metric": "settle", "value": med(vals), "rating": rate(med(vals), budget),
                "settle": stats(vals), "first_output": stats([t["first_output_ms"] for t in tls]),
                "rss_kb": med([t["rss_kb"] for t in tls]), "samples": vals,
            })
            continue
        acts = by.get(gid)
        if not acts:
            continue
        title, kind, budget = GROUP_INFO[gid]
        g = {"id": gid, "title": title, "kind": kind, "budget_ms": budget, "n": len(acts)}
        for m in ("paint_ms", "settle_ms", "busy_ms", "queue_ms", "cpu_ms", "frames", "bytes"):
            g[m[:-3] if m.endswith("_ms") else m] = stats([a.get(m) for a in acts])
        g["samples"] = [a.get("settle_ms") for a in acts if a.get("settle_ms") is not None]
        # the number the rating uses: what the user waits for in this kind of interaction
        metric = "settle" if kind in ("nav", "resize", "shutdown", "startup") else "paint"
        if g.get(metric) is None or g[metric]["n"] < max(1, len(acts) // 4):
            metric = "busy" if g.get("busy") else "settle"
        g["metric"] = metric
        g["value"] = g[metric]["med"] if g.get(metric) else None
        g["rating"] = rate(g["value"], budget)
        g["no_effect"] = sum(1 for a in acts if a.get("ok") is False and not a.get("went", True))
        g["went_false"] = sum(1 for a in acts if a.get("went") is False) if kind == "nav" else 0
        g["details"] = _details(acts)
        if gid == "nav.key" and g["went_false"] == len(acts):
            g["rating"], g["note"] = "slow", "key does nothing: no page change"
        if gid == "idle":
            secs = sum(a.get("idle_s", 0) for a in acts) or 1
            g["idle"] = {"frames_per_s": sum(a["frames"] for a in acts) / secs,
                         "bytes_per_s": sum(a["bytes"] for a in acts) / secs,
                         "cpu_pct": sum(a["cpu_ms"] for a in acts) / (secs * 10),
                         "busy_pct": sum(a["busy_ms"] for a in acts) / (secs * 10)}
        groups.append(g)
    return groups


def _details(acts):
    by = {}
    for a in acts:
        by.setdefault(a["detail"], []).append(a)
    out = []
    for d, xs in by.items():
        out.append({"detail": d, "settle": med([x.get("settle_ms") for x in xs if x.get("settle_ms") is not None]),
                    "busy": med([x.get("busy_ms") for x in xs if x.get("busy_ms") is not None]),
                    "frames": med([x.get("frames") for x in xs if x.get("frames") is not None]),
                    "bytes": med([x.get("bytes") for x in xs if x.get("bytes") is not None])})
    return out


def startup_view(rounds):
    out = {}
    for which in ("cold", "warm"):
        tls = [r["startup"][which] for r in rounds if which in r["startup"] and r["startup"][which].get("ready_ms")]
        if not tls:
            continue
        labels = []
        for tl in tls:
            for lab, s, e in tl["spans"]:
                if lab not in labels:
                    labels.append(lab)
        spans = []
        for lab in labels:
            ss = [next((s for l, s, e in tl["spans"] if l == lab), None) for tl in tls]
            ee = [next((e for l, s, e in tl["spans"] if l == lab), None) for tl in tls]
            ss, ee = [x for x in ss if x is not None], [x for x in ee if x is not None]
            if ss and ee:
                spans.append({"label": lab, "start": med(ss), "end": med(ee)})
        out[which] = {"ready_ms": med([t["ready_ms"] for t in tls]), "spans": spans,
                      "first_output_ms": med([t["first_output_ms"] for t in tls if t["first_output_ms"]]),
                      "rss_kb": med([t["rss_kb"] for t in tls])}
    return out


# ── attribution ──────────────────────────────────────────────────────────────
def _calibration(group_id, latency, trace_actions, bucket, global_k):
    """Factor that maps traced in-shell time back to real time for one scenario.
    real busy per action (untraced probes) = k * shell_traced + external + fork (those two are not inflated)."""
    g = latency.get(group_id)
    tot = bucket["tot"]
    n = max(1, trace_actions.get(group_id, 1))
    real_ms = None
    if g:
        if group_id.startswith("startup"):
            real_ms = g["value"]
        elif g.get("busy"):
            real_ms = g["busy"]["mean"]
    # blocking (`read -t` debounce, `wait`) sits inside the untraced busy window but is not shell work:
    # leaving it in inflates k (resize debounces ~45 ms inside _tui._apply_resize)
    sh, ex, fk = tot["sh"] / n / 1000, tot["ex"] / n / 1000, tot["fk"] / n / 1000
    wt = (tot["wait"] + tot["idle"]) / n / 1000
    if real_ms is None or sh <= 0:
        return global_k, None
    k = (real_ms - ex - fk - wt) / sh
    if k <= 0:
        k = real_ms / max(sh + ex + fk + wt, 1e-9)
    return max(0.03, min(1.0, k)), real_ms


def attribution(traces, latency_list, repo_files):
    """traces: list of trace dicts ({'trace': aggregator result, 'actions': [...]}) -> attribution view."""
    latency = {g["id"]: g for g in latency_list}
    funcfile = {}
    buckets = {}
    n_actions = {}
    for t in traces:
        if not t or not t.get("trace"):
            continue
        funcfile.update(t["trace"]["funcfile"])
        for key, b in t["trace"]["buckets"].items():
            buckets[key] = b
        for a in t.get("actions", []):
            n_actions[a["group"]] = n_actions.get(a["group"], 0) + 1

    def file_of(f):
        return funcfile.get(f) or ("" if f.startswith("⟨") else "")

    # global k: pooled over every interaction group
    num = den = 0.0
    for key, b in buckets.items():
        gid, kind = key.rsplit("|", 1)
        if kind != "w" or gid.startswith("startup") or gid not in latency or not latency[gid].get("busy"):
            continue
        n = max(1, n_actions.get(gid, 1))
        sh = b["tot"]["sh"] / n / 1000
        rest = (b["tot"]["ex"] + b["tot"]["fk"] + b["tot"]["wait"] + b["tot"]["idle"]) / n / 1000
        num += max(0.0, latency[gid]["busy"]["mean"] - rest) * n
        den += sh * n
    global_k = max(0.03, min(1.0, num / den)) if den else 0.25

    out = {"global_k": global_k, "groups": {}, "files": funcfile}
    total_calls = {}
    fn_tot = {}
    edge_tot = {}
    flow = {}
    hot_lines = {}
    execs = {}
    forks = {}
    for key, b in sorted(buckets.items()):
        gid, kind = key.rsplit("|", 1)
        if gid == "-" or gid not in latency:   # setup steps and unselected starts are traced but not reported
            continue
        n = max(1, n_actions.get(gid, 1))
        k, real = _calibration(gid, latency, n_actions, b, global_k) if kind == "w" else (global_k, None)
        gv = out["groups"].setdefault(gid, {})
        view = {"k": k, "real_ms": real, "n_actions": n, "traced_ms": {kk: v / 1000 for kk, v in b["tot"].items()},
                "lines": b["nlines"], "pids": b["pids"]}
        layers = {}
        stacks = []
        self_ms = {}
        incl_ms = {}
        per_ms = 1.0 / n / 1000.0
        blocked = {}
        for (frames, kk), (us, cnt) in b["stacks"].items():
            if kk in ("idle", "wait"):
                for f in set(frames):
                    blocked[f] = blocked.get(f, 0.0) + us * per_ms
                continue
            real_ms_entry = us * per_ms * (k if kk == "sh" else 1.0)
            leaf = frames[-1]
            if kk.startswith("ex:"):
                frames = frames + ("⟨" + kk[3:] + "⟩",)
                leaf_layer = "process"
            elif kk == "fk":
                frames = frames + ("⟨fork⟩",)
                leaf_layer = "process"
            else:
                leaf_layer = layer_of(leaf, file_of(leaf))
            layers[leaf_layer] = layers.get(leaf_layer, 0.0) + real_ms_entry
            stacks.append((frames, real_ms_entry))
            top = frames[-1]
            self_ms[top] = self_ms.get(top, 0.0) + real_ms_entry
            for f in set(frames):
                incl_ms[f] = incl_ms.get(f, 0.0) + real_ms_entry
            if kind == "w":
                # layer flow: time passing from one layer into the next one down the stack
                prev_layer = None
                for f in frames:
                    ly = "process" if f.startswith("⟨") else layer_of(f, file_of(f))
                    if prev_layer is not None and ly != prev_layer:
                        flow[(prev_layer, ly)] = flow.get((prev_layer, ly), 0.0) + real_ms_entry
                    prev_layer = ly
                for a, c in zip(frames, frames[1:]):
                    edge_tot[(a, c)] = edge_tot.get((a, c), 0.0) + real_ms_entry
        view["layers"] = layers
        view["total_ms"] = sum(layers.values())
        view["self"] = self_ms
        view["incl"] = incl_ms
        view["blocked"] = blocked
        if kind == "w" or gid == "idle":
            view["stacks"] = stacks
        gv[kind] = view
        if kind != "w":
            continue
        for fn, c in b["calls"].items():
            total_calls.setdefault(fn, {})[gid] = c / n
        for fn in self_ms:
            fn_tot.setdefault(fn, {})[gid] = (self_ms[fn], incl_ms.get(fn, 0.0))
        for src, (sh, ex, fk, hits) in b["lines"].items():
            e = hot_lines.setdefault(src, {"sh": 0.0, "ex": 0.0, "fk": 0.0, "hits": 0, "groups": {}})
            ms = (sh * k + ex + fk) / n / 1000
            e["sh"] += sh * k / n / 1000
            e["ex"] += ex / n / 1000
            e["fk"] += fk / n / 1000
            e["hits"] += hits / n
            e["groups"][gid] = ms
        for (word, fn), (cnt, us) in b["execs"].items():
            e = execs.setdefault((word, fn), {"count": 0.0, "ms": 0.0, "groups": {}})
            e["count"] += cnt / n
            e["ms"] += us / n / 1000
            e["groups"][gid] = cnt / n
        for (fn, src), cnt in b["forks"].items():
            e = forks.setdefault((fn, src), {"count": 0.0, "groups": {}})
            e["count"] += cnt / n
            e["groups"][gid] = cnt / n

    out["functions"] = _function_table(fn_tot, total_calls, funcfile)
    out["edges"] = sorted(({"from": a, "to": b_, "ms": v} for (a, b_), v in edge_tot.items()), key=lambda d: -d["ms"])[:60]
    out["flow"] = [{"from": a, "to": b_, "ms": v} for (a, b_), v in sorted(flow.items(), key=lambda kv: -kv[1])]
    out["hot_lines"] = _hot_lines(hot_lines)
    out["execs"] = sorted(({"cmd": w, "caller": f, "layer": layer_of(f, file_of(f)), **v}
                           for (w, f), v in execs.items()), key=lambda d: -d["ms"])
    by_fn = {}
    for (f, s), v in forks.items():
        e = by_fn.setdefault(f, {"func": f, "count": 0.0, "groups": {}, "sites": {}})
        e["count"] += v["count"]
        e["sites"][s] = e["sites"].get(s, 0.0) + v["count"]
        for g, n_ in v["groups"].items():
            e["groups"][g] = e["groups"].get(g, 0.0) + n_
    for e in by_fn.values():
        e["src"] = max(e["sites"], key=e["sites"].get)
        e["n_sites"] = len(e.pop("sites"))
        e["layer"] = layer_of(e["func"], file_of(e["func"]))
    out["forks"] = sorted(by_fn.values(), key=lambda d: -d["count"])
    return out


def _function_table(fn_tot, calls, funcfile):
    rows = []
    for fn, per in fn_tot.items():
        self_ms = sum(v[0] for v in per.values())
        incl_ms = sum(v[1] for v in per.values())
        ncalls = sum(calls.get(fn, {}).values())
        rows.append({"name": fn, "file": funcfile.get(fn, ""), "layer": layer_of(fn, funcfile.get(fn, "")),
                     "self_ms": self_ms, "incl_ms": incl_ms, "calls": ncalls,
                     "per_call_us": (self_ms / ncalls * 1000) if ncalls else None,
                     "groups": {g: v[0] for g, v in per.items()}})
    rows.sort(key=lambda r: -r["self_ms"])
    return rows[:200]


def _hot_lines(hl):
    from .session import REPO
    cache = {}

    def snippet(src):
        f, _, ln = src.partition(":")
        if f not in cache:
            cache[f] = None
            for root in ("lib", "share/demo", "bin", "share/defaults"):
                for dp, _, fs in os.walk(os.path.join(REPO, root)):
                    if f in fs:
                        try:
                            cache[f] = open(os.path.join(dp, f), errors="replace").read().split("\n")
                        except OSError:
                            pass
                        break
                if cache[f]:
                    break
        lines = cache[f]
        try:
            return lines[int(ln) - 1].strip()[:110] if lines else ""
        except (ValueError, IndexError):
            return ""

    rows = [{"src": s, "ms": v["sh"] + v["ex"] + v["fk"], "hits": v["hits"], "ex_ms": v["ex"], "fk_ms": v["fk"],
             "groups": v["groups"]} for s, v in hl.items()]
    rows.sort(key=lambda r: -r["ms"])
    rows = rows[:60]
    for r in rows:
        r["code"] = snippet(r["src"])
    return rows


# ── trees, paths, report assembly ────────────────────────────────────────────
def flame_tree(stacks, min_ms):
    """stacks: [(frames, ms)] -> nested {n, v, c:[...]} pruned below min_ms (folded into 'other')."""
    root = {"n": "all", "v": 0.0, "c": {}}
    for frames, ms in stacks:
        root["v"] += ms
        node = root
        for f in frames:
            nxt = node["c"].get(f)
            if nxt is None:
                nxt = node["c"][f] = {"n": f, "v": 0.0, "c": {}}
            nxt["v"] += ms
            node = nxt

    def fin(node):
        kids = sorted(node["c"].values(), key=lambda x: -x["v"])
        keep = [k for k in kids if k["v"] >= min_ms]
        rest = sum(k["v"] for k in kids if k["v"] < min_ms)
        out = [fin(k) for k in keep]
        if rest > 0:
            out.append({"n": "…small", "v": rest, "c": []})
        return {"n": node["n"], "v": node["v"], "c": out}

    return fin(root)


def hot_path(tree, depth=9):
    """Heaviest child chain: the answer to 'where does it go' in one line."""
    path, node = [], tree
    while node["c"] and len(path) < depth:
        node = max(node["c"], key=lambda c: c["v"])
        if node["n"] == "…small":
            break
        path.append((node["n"], node["v"]))
    return path


def merge_views(group_views):
    """Sum several group views into one (for the 'all interactions' flame)."""
    stacks = []
    for v in group_views:
        stacks.extend(v.get("stacks", []))
    return stacks


def calibration_check(rounds, attr):
    """Untraced probe time of each wrapped function vs what the rescaled trace says it costs.
    Both are per action of the scenario; a large error means the shell-time factor is off for that code."""
    real = {}
    counts = {}
    for r in rounds:
        for a in r["actions"]:
            g = a["group"]
            if g.startswith("startup") or g in ("idle", "shutdown"):
                continue
            counts[g] = counts.get(g, 0) + 1
            for fn, ms in (a.get("spans") or {}).items():
                real.setdefault((g, fn), 0.0)
                real[(g, fn)] += ms
    rows = []
    for (g, fn), tot in real.items():
        w = attr["groups"].get(g, {}).get("w")
        if not w:
            continue
        r_ms = tot / counts[g]
        est = w["incl"].get(fn, 0.0) + w.get("blocked", {}).get(fn, 0.0)   # probes time wall clock, blocking included
        if r_ms < 1.0 and est < 1.0:
            continue
        rows.append({"group": g, "func": fn, "real_ms": r_ms, "est_ms": est,
                     "err_pct": (est - r_ms) / r_ms * 100 if r_ms else None})
    rows.sort(key=lambda x: -x["real_ms"])
    rows = rows[:60]
    scored = [x for x in rows if x["err_pct"] is not None and x["real_ms"] >= 2.0]
    wsum = sum(x["real_ms"] for x in scored)
    return {"rows": rows,
            "mae_pct": sum(abs(x["err_pct"]) * x["real_ms"] for x in scored) / wsum if wsum else None,
            "bias_pct": sum(x["err_pct"] * x["real_ms"] for x in scored) / wsum if wsum else None,
            "n": len(scored)}


def build_report(meta, rounds, traces, baseline=None):
    from . import insights
    lat = latency_groups(rounds)
    start = startup_view(rounds)
    attr = attribution(traces, lat, None)
    report = {"meta": meta, "latency": lat, "startup": start, "attr": attr, "warnings": meta.get("warnings", []),
              "calibration": calibration_check(rounds, attr) if traces else None}
    # trees for the flame graphs: one per scenario group, plus everything the user triggered
    trees, paths = {}, {}
    work = []
    for gid, gv in attr["groups"].items():
        w = gv.get("w")
        if not w or not w.get("stacks"):
            continue
        total = w["total_ms"]
        trees[gid] = flame_tree(w["stacks"], total * 0.004)
        paths[gid] = hot_path(trees[gid])
        if not gid.startswith("startup"):
            work.append(w)
    if work:
        allst = merge_views(work)
        trees["*all interactions"] = flame_tree(allst, sum(m for _, m in allst) * 0.003)
        paths["*all interactions"] = hot_path(trees["*all interactions"])
    idle = attr["groups"].get("idle", {}).get("a")
    if idle and idle.get("stacks"):
        trees["idle (ambient)"] = flame_tree(idle["stacks"], idle["total_ms"] * 0.004)
        paths["idle (ambient)"] = hot_path(trees["idle (ambient)"])
    report["trees"], report["paths"] = trees, paths
    for gv in attr["groups"].values():   # stacks are only needed to build the trees
        for v in gv.values():
            v.pop("stacks", None)
    report["insights"] = insights.generate(report)
    report["compare"] = compare(report, baseline) if baseline else None
    return report


def compare(report, base):
    """Per-group delta of the headline latency against an earlier report.json."""
    old = {g["id"]: g for g in base.get("latency", [])}
    rows = []
    for g in report["latency"]:
        if g["id"] == "idle":
            continue
        o = old.get(g["id"])
        if not o or o.get("value") is None or g.get("value") is None:
            continue
        rows.append({"id": g["id"], "title": g["title"], "old": o["value"], "new": g["value"],
                     "delta_pct": (g["value"] - o["value"]) / o["value"] * 100 if o["value"] else 0.0})
    return {"when": base.get("meta", {}).get("when"), "commit": base.get("meta", {}).get("commit"), "rows": rows}
