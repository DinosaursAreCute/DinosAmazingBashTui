#!/usr/bin/env python3
"""Builds docs/concepts/performance-explorer.html (the interactive performance page of the documentation site)
from saved profiler reports: tools/profiler/site/explorer.template.html + the data below.

    python3 tools/profiler/site_export.py            # write the page
    python3 tools/profiler/site_export.py --list     # show which reports are used

Each revision names the report (a tools/profiler/reports/<dir>) measured closest after that change. Only runs
that were traced (deep, or --cold-trace) carry layers, hot functions and flame graphs.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
REPORTS = os.path.join(HERE, "reports")
TEMPLATE = os.path.join(HERE, "site", "explorer.template.html")
OUT = os.path.join(REPO, "docs", "concepts", "performance-explorer.html")
sys.path.insert(0, HERE)
from dprof.analyze import LAYERS  # noqa: E402

REVISIONS = [
    ("base", "Baseline", "20260930-193435", "The first deep run, before any change.", True),
    ("c1-2", "Changes 1-2", "20260930-204936", "Colour memo and a fork-free pane renderer (no awk in _render_output_buf).", False),
    ("c3-4", "Changes 3-4", "20260930-205743", "Idle overlay redraw loop fixed; pane interiors built once per render.", False),
    ("c5", "Change 5", "20260930-213033", "Cached pages skip the per-widget style re-bake when the theme is unchanged.", False),
    ("c6-7", "Changes 6-7", "20260930-214915", "Page key bindings survive a cache replay; input settle timeout replaces a 50 ms idle wait.", True),
    ("c8", "Change 8", "20260930-215938", "One stat call per cache check and fork-free cache loading.", False),
    ("c9", "Change 9", "20260930-221040", "Layout: one pass for content fit instead of panes x widgets, twice.", False),
    ("c10", "Change 10", "20260930-222311", "Widgets of one pane share the pane inset during render and hit tests.", False),
    ("c11", "Change 11", "20260930-223251", "No render inside on_visit; fork-free docs page titles.", False),
    ("c12", "Change 12", "20260930-225600", "Fork-free page build, cheaper process-tree kill on leaving the Terminal page.", False),
    ("c13", "Change 13", "20260930-230441", "Remaining cold-start forks in the cache recording removed.", False),
    ("c13d", "Deep run after 13", "20260930-231054", "Deep run after the first thirteen changes.", True),
    ("c14", "Change 14", "20261001-183844", "Content-addressed fragment cache: panes, labels, buttons and checkboxes are composed once per distinct input.", True),
    ("c15-16", "Changes 15-16", "20261001-195825", "Overlay dismissal replays the saved frame; widget geometry and coloured-line slice memos.", True),
    ("c17", "Change 17", "20261001-201315", "Demo callbacks without forks, memoised renderer views, one navbar width, fork-free output measuring (deep run).", True),
    ("c18", "Change 18", "20261001-204153", "Trusted cache, ten-page switch by key (nav run, 10 rounds): the build of v0.0.21.", False),
    ("c19", "Changes 19-20", "20261001-222623", "Snapshot rewritten once, no stty per switch, fragment keys without the epoch (full run, 2 rounds).", False),
    ("latest", "v0.0.22 deep run", "20261001-230749", "Footer written only on change, relayout skipped at the recorded size, widget draw overhead; includes the page-switch floor scenario (deep run, 5 rounds, idle machine).", True),
    # DevEx Update 2: deep runs, full scenario, 5 rounds, with the held-key groups. held0 is the same build without
    # the focus work (the only before for the held groups); devex2 is the newest deep run.
    ("held0", "Stage 2 without the focus work", "20261002-222307", "Page templates, addons, refresh and the hit/focus index; a focus move still redraws the pane border and diffs every frame, and arrow-key search recomputes every widget position.", True),
    ("devex2", "DevEx Update 2", "20261002-223527", "Stage 2 of markup v2 (templates, addons, refresh, hit and focus index) and the held-key work: a focus move paints its known dirty rows as one raw frame and skips the pane border inside a pane; arrow-key search reads cached widget rects.", True),
    # DevEx Update 4: the build with the background render of Markdown documents and cached pictures (runs after 23:00 on 5 Nov).
    ("devex4-nav", "DevEx Update 4, page switches", "20261105-230830", "Markdown renderer with documents rendered by a background process and cached pictures; the ten-page switch by click and by key (nav run, 2 rounds, traced).", True),
    ("devex4-floor", "DevEx Update 4, page-switch floor", "20261105-233707", "The page-switch floor on the same build (quick run, traced).", True),
    ("devex4", "DevEx Update 4", "20261105-234102", "The Markdown renderer, documents rendered by a background process, cached pictures, cheaper fused-pane frames and the select widget fix (full run, 2 rounds, traced).", True),
    # Start-up work (6-7 Nov): parallel and background validation, the lazy cache build, theme dedupe and the log level.
    ("startup", "Start-up work", "20261107-012148", "Cold start 4.3 s to 1.4 s: page validation in parallel and in the background, only the first page built behind the splash with the rest built by a background pool (links first), each theme loaded once, `info` log level by default (full run, deep, 5 rounds).", True),
    # Scroll work (7 Nov): the widgets pane, scroll scenario, 2 rounds. scroll-base is the build before it.
    ("scroll-base", "Scrolling, before", "20261107-163431", "Every wheel tick repaints and re-places every widget of the pane, off-screen ones included (scroll scenario, 2 rounds, traced).", True),
    ("scroll1", "Scrolling 1: off-screen widgets", "20261107-165112", "The pane repaint skips widgets above or below the viewport before placing them; pinned widget kept (scroll scenario, untraced).", False),
    ("scroll2", "Scrolling 2: placement cache", "20261107-170116", "The widget placement cache no longer keys on the scroll offset; the offset, pin and clip are applied after the lookup (scroll scenario, traced).", True),
    ("scroll4", "Scrolling 3: hit zones", "20261107-170910", "The hit index skips widgets that cannot be hit above or below the viewport instead of placing and clipping all of them (scroll scenario, traced).", True),
    ("scroll5", "Scrolling 4: pin and measure", "20261107-171651", "The pinned-widget search walks only the pins; the content measure drops per-widget locals and the regex (scroll scenario, traced).", True),
    ('r20261112-213012', 'Performance Optimizations', '20261112-213012', 'Performance Optimizations', True),
]


def r1(x, n=1):
    return None if x is None else round(x, n)


def prune(node, total, depth=0):
    """Flame tree without slivers: nodes below 0.4% of the whole run are dropped, depth capped."""
    out = {"n": node["n"], "v": r1(node["v"], 2)}
    kids = [c for c in node.get("c", []) if c["v"] >= total * 0.004]
    if depth < 16 and kids:
        out["c"] = [prune(c, total, depth + 1) for c in sorted(kids, key=lambda c: -c["v"])]
    return out


def load(rev):
    key, label, run, desc, deep = rev
    rep = json.load(open(os.path.join(REPORTS, run, "report.json")))
    lat = {}
    pages = {}
    idle = None
    for g in rep["latency"]:
        gid = g["id"]
        if gid == "idle":
            i = g.get("idle") or {}
            idle = {"fps": r1(i.get("frames_per_s")), "kbps": r1((i.get("bytes_per_s") or 0) / 1024), "cpu": r1(i.get("cpu_pct"))}
            continue
        if g.get("value") is None:
            continue
        lat[gid] = {
            "t": g["title"], "v": r1(g["value"], 2), "b": g["budget_ms"], "n": g["n"],
            "fr": r1((g.get("frames") or {}).get("med") or 0), "kb": r1(((g.get("bytes") or {}).get("med") or 0) / 1024),
        }
        if gid in ("nav.first", "nav.revisit"):
            pages[gid] = {d["detail"]: r1(d["settle"], 0) for d in g.get("details", [])}
    start = {}
    for w in ("cold", "warm"):
        t = (rep.get("startup") or {}).get(w)
        if t:
            start[w] = [[s["label"], r1(s["end"] - s["start"], 0)] for s in t["spans"]]
    out = {"id": key, "label": label, "run": run, "when": rep["meta"].get("when", ""), "desc": desc, "deep": deep,
           "lat": lat, "idle": idle, "pages": pages, "start": start}
    attr = rep.get("attr") or {}
    if deep and attr.get("groups"):
        layers = {}
        for gid, gv in attr["groups"].items():
            w = gv.get("w")
            if w:
                layers[gid] = {"total": r1(w["total_ms"]), "layers": {k: r1(v) for k, v in w["layers"].items() if v >= 0.05}}
        funcs = sorted(attr["functions"], key=lambda f: -f["self_ms"])[:90]
        out["layers"] = layers
        out["funcs"] = [[f["name"], f["layer"], r1(f["self_ms"]), r1(f["incl_ms"]), r1(f["calls"], 0)] for f in funcs]
        tree = (rep.get("trees") or {}).get("*all interactions")
        if tree:
            out["tree"] = prune(tree, tree["v"])
        out["k"] = r1(attr.get("global_k"), 2)
    return out


def main():
    if "--list" in sys.argv:
        for rev in REVISIONS:
            print(rev[0], rev[2], "deep" if rev[4] else "")
        return 0
    runs = [load(r) for r in REVISIONS]
    data = {"runs": runs, "layers": {k: v[0] for k, v in LAYERS.items()}}
    blob = json.dumps(data, separators=(",", ":"), ensure_ascii=False).replace("</", "<\\/")
    tpl = open(TEMPLATE, encoding="utf-8").read()
    if "/*DATA*/" not in tpl:
        print("template has no /*DATA*/ marker", file=sys.stderr)
        return 1
    html = tpl.replace("/*DATA*/null", blob)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write(html)
    print(f"wrote {os.path.relpath(OUT, REPO)}  {len(html) / 1024:.0f} KB  {len(runs)} runs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
