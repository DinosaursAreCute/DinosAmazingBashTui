#!/usr/bin/env python3
"""Draws DABT-styled SVG charts (pixel-cell bars, brand colours) from compare-v2 results.json files.

    python3 charts.py                       # latest run in reports/ -> <run>/charts/
    python3 charts.py RUN_DIR|results.json  # a given run
    python3 charts.py RUN [-o DIR] [-m ready_ms|first_byte_ms|first_paint_ms|settled_ms]

Writes hero.svg (vertical pillars of the user-felt actions, for the front page), summary.svg (headline cards: median step time, wins, startup, idle CPU, memory) and latency.svg
(every step grouped by prefix, one bar per app, the slowest app fills the row). Stdlib only.
"""
import argparse
import glob
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BG, CARD, LINE = "#0b0f14", "#141c26", "#22303f"
FG, MUT = "#d7e0ea", "#8497ab"
PINK, BLUE, YELLOW, CORAL = "#ff8cbf", "#a8d8ff", "#fff3a8", "#ff9e9e"
PALETTE = [PINK, BLUE, YELLOW, CORAL]
FONT = "'JetBrains Mono',ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"
PITCH, CW, N = 12, 10, 40  # cell pitch, cell width, cells per full bar


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def fmt_ms(v):
    if v >= 1000:
        return f"{v / 1000:.2f} s"
    return f"{v:.1f} ms" if v < 100 else f"{v:.0f} ms"


def load(arg):
    if arg is None:
        runs = sorted(glob.glob(os.path.join(HERE, "reports", "*", "results.json")))
        if not runs:
            sys.exit("no reports/*/results.json found")
        arg = runs[-1]
    path = os.path.join(arg, "results.json") if os.path.isdir(arg) else arg
    with open(path, encoding="utf-8") as f:
        return path, json.load(f)


def med(entries, key):
    """Median of key over the ok, non-stale entries of one step; None when there is none."""
    vals = [e[key] for e in entries if e.get("ok") and not e.get("stale") and e.get(key) is not None]
    return statistics.median(vals) if vals else None


def collect(res, metric):
    """-> apps [(data_key, label, color)], steps [(name, {app_label: ms|None})], idle/mem per app."""
    meta_apps = res["meta"]["apps"]
    apps = [(a["name"], a["label"], PALETTE[i % len(PALETTE)]) for i, a in enumerate(meta_apps)]
    steps = []
    for s in res["steps"]:
        if s["kind"] != "latency":
            continue
        steps.append((s["name"], {lab: med(res["data"].get(k, {}).get(s["name"], []), metric) for k, lab, _ in apps}))
    extra = {}
    for k, lab, _ in apps:
        d = res["data"].get(k, {})
        idle = next((v for v in d.values() if v and v[0]["kind"] == "idle"), [])
        mem = next((v for v in d.values() if v and v[0]["kind"] == "memory"), [])
        extra[lab] = {"cpu": med(idle, "cpu_pct"), "wake": med(idle, "wakeups_s"), "pss": med(mem, "pss_kb")}
    return apps, steps, extra


def cells(x, y, n, color, h, opacity=1.0):
    return "".join(f'<rect x="{x + i * PITCH}" y="{y}" width="{CW}" height="{h}" fill="{color}" opacity="{opacity}"/>' for i in range(n))


def frame(w, h, title, sub):
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" shape-rendering="crispEdges" font-family="{FONT}">',
        f'<rect width="{w}" height="{h}" fill="{BG}"/>',
        f'<rect x="1" y="1" width="{w - 2}" height="{h - 2}" fill="{CARD}" stroke="{LINE}" stroke-width="2"/>',
        f'<rect x="1" y="1" width="{w - 2}" height="6" fill="{PINK}"/>',
        f'<rect x="{w // 3}" y="1" width="{w // 3}" height="6" fill="{BLUE}"/>',
        f'<rect x="{2 * w // 3}" y="1" width="{w // 3 - 1}" height="6" fill="{YELLOW}"/>',
        f'<text x="32" y="50" font-size="22" font-weight="700" fill="{FG}">{esc(title)}</text>',
        f'<text x="32" y="74" font-size="13" fill="{MUT}">{esc(sub)}</text>',
    ]


def legend(svg, apps, y):
    x = 32
    for _, lab, col in apps:
        svg.append(f'<rect x="{x}" y="{y - 10}" width="14" height="10" fill="{col}"/><text x="{x + 22}" y="{y}" font-size="12" fill="{MUT}">{esc(lab)}</text>')
        x += 40 + 8 * len(lab)


def subtitle(res, metric):
    m = res["meta"]
    return f"{m['scenario']} &#183; {m['cols']}x{m['rows']} &#183; {m['rounds']} round(s) &#183; {metric} (median) &#183; lower is better"


def chart_latency(res, apps, steps, metric):
    W, x0, top, bar_h = 980, 232, 104, 12
    block = len(apps) * (bar_h + 1) + 12
    groups = {}
    for name, vals in steps:
        groups.setdefault(name.split(".")[0], []).append((name, vals))
    H = top + sum(34 + len(v) * block for v in groups.values()) + 64
    svg = frame(W, H, "STEP LATENCY", "")
    svg[-1] = f'<text x="32" y="74" font-size="13" fill="{MUT}">{subtitle(res, metric)}</text>'
    y = top
    for g, items in groups.items():
        svg.append(f'<text x="32" y="{y + 16}" font-size="15" font-weight="700" fill="{YELLOW}">{esc(g.upper())}</text>')
        svg.append(f'<rect x="32" y="{y + 24}" width="{W - 64}" height="2" fill="{LINE}"/>')
        y += 34
        for name, vals in items:
            top_v = max((v for v in vals.values() if v), default=0)
            svg.append(f'<text x="32" y="{y + 12}" font-size="12" font-weight="700" fill="{FG}">{esc(name)}</text>')
            for i, (_, lab, col) in enumerate(apps):
                v, by = vals[lab], y + i * (bar_h + 1)
                svg.append(cells(x0, by + 1, N, BLUE, bar_h - 3, 0.18))
                if v is None:
                    svg.append(f'<text x="{x0 + 4}" y="{by + 10}" font-size="11" font-weight="700" fill="{CORAL}">FAIL</text>')
                    continue
                n = max(1, round(v / top_v * N)) if top_v else 1
                svg.append(cells(x0, by + 1, n, col, bar_h - 3))
                best = v == min(x for x in vals.values() if x)
                svg.append(f'<text x="{x0 + N * PITCH + 14}" y="{by + 10}" font-size="11" fill="{col if best else MUT}" font-weight="{700 if best else 400}">{fmt_ms(v)}</text>')
            y += block
    legend(svg, apps, H - 30)
    svg.append("</svg>")
    return "\n".join(svg)


def chart_summary(res, apps, steps, extra, metric):
    W, x0, row = 980, 232, 54
    labs = [lab for _, lab, _ in apps]
    stats = {}
    for lab in labs:
        vals = [v[lab] for _, v in steps if v[lab] is not None]
        wins = sum(1 for _, v in steps if v[lab] is not None and v[lab] == min(x for x in v.values() if x is not None))
        start = {n: v[lab] for n, v in steps if n.startswith("startup.")}
        stats[lab] = {"med": statistics.median(vals) if vals else None, "wins": wins, "fails": sum(1 for _, v in steps if v[lab] is None),
                      "cold": start.get("startup.cold"), "warm": start.get("startup.warm")}
    rows = [
        ("MEDIAN STEP", {l: stats[l]["med"] for l in labs}, fmt_ms),
        ("COLD START", {l: stats[l]["cold"] for l in labs}, fmt_ms),
        ("WARM START", {l: stats[l]["warm"] for l in labs}, fmt_ms),
        ("IDLE CPU", {l: extra[l]["cpu"] for l in labs}, lambda v: f"{v:.2f} %"),
        ("MEMORY (PSS)", {l: extra[l]["pss"] for l in labs}, lambda v: f"{v / 1024:.1f} MB"),
    ]
    H = 104 + len(rows) * row + 56 + len(labs) * 30 + 64
    svg = frame(W, H, "HEAD TO HEAD", "")
    svg[-1] = f'<text x="32" y="74" font-size="13" fill="{MUT}">{subtitle(res, metric)}</text>'
    for i, (title, vals, f) in enumerate(rows):
        y = 104 + i * row
        top_v = max((v for v in vals.values() if v), default=0)
        svg.append(f'<text x="32" y="{y + 19}" font-size="13" font-weight="700" fill="{FG}">{title}</text>')
        for j, (_, lab, col) in enumerate(apps):
            v, by = vals[lab], y + j * 15
            svg.append(cells(x0, by + 2, N, BLUE, 9, 0.18))
            if v is None:
                svg.append(f'<text x="{x0 + 4}" y="{by + 11}" font-size="11" font-weight="700" fill="{CORAL}">n/a</text>')
                continue
            n = max(1, round(v / top_v * N)) if top_v else 1
            svg.append(cells(x0, by + 2, n, col, 9))
            best = v == min(x for x in vals.values() if x is not None)
            svg.append(f'<text x="{x0 + N * PITCH + 14}" y="{by + 11}" font-size="11" fill="{col if best else MUT}" font-weight="{700 if best else 400}">{f(v)}</text>')
    y = 104 + len(rows) * row + 8
    svg.append(f'<rect x="32" y="{y}" width="{W - 64}" height="2" fill="{LINE}"/>')
    svg.append(f'<text x="32" y="{y + 30}" font-size="15" font-weight="700" fill="{YELLOW}">STEPS WON</text>')
    svg.append(f'<text x="32" y="{y + 48}" font-size="12" fill="{MUT}">fastest app per step, out of {len(steps)} &#183; fails count as lost</text>')
    for j, (_, lab, col) in enumerate(apps):
        by = y + 62 + j * 30
        s = stats[lab]
        svg.append(f'<text x="32" y="{by + 14}" font-size="13" font-weight="700" fill="{FG}">{esc(lab.upper())}</text>')
        svg.append(cells(x0, by + 2, N, BLUE, 14, 0.18))
        svg.append(cells(x0, by + 2, round(s["wins"] / max(1, len(steps)) * N), col, 14))
        extra_t = f" &#183; {s['fails']} fail" if s["fails"] else ""
        svg.append(f'<text x="{x0 + N * PITCH + 14}" y="{by + 14}" font-size="13" font-weight="700" fill="{col}">{s["wins"]}{extra_t}</text>')
    legend(svg, apps, H - 30)
    svg.append("</svg>")
    return "\n".join(svg)


# front-page picture: what a user feels. (title, steps whose per-app medians are averaged by median)
HERO = [
    ("PAGE SWITCH", ["nav.tasks", "nav.notes", "nav.logs", "nav.settings", "nav.admin",
                     "revisit.overview", "revisit.tasks", "revisit.notes", "revisit.settings", "revisit.admin"]),
    ("KEY PRESS", ["table.down", "table.pagedown", "table.top", "list.pagedown", "list.end", "list.home", "tab.appearance", "tab.general"]),
    ("TYPING", ["filter.char", "form.type", "editor.word", "palette.type"]),
    ("DIALOG + PALETTE", ["dialog.open", "dialog.confirm", "palette.open", "palette.run"]),
    ("THEME SWITCH", ["theme.light", "theme.dark"]),
]


def short(v, unit):
    if unit == "%":
        return f"{v:.2f}%"
    if unit == "MB":
        return f"{v:.0f}MB"
    if v >= 1000:
        return f"{v / 1000:.1f}s"
    return f"{v:.1f}ms" if v < 10 else f"{v:.0f}ms"


def chart_hero(res, apps, steps, extra, metric):
    """Vertical pillars, one cluster per user-facing action; each cluster is scaled to its slowest app."""
    by_name = dict(steps)
    labs = [lab for _, lab, _ in apps]
    clusters = []
    for title, names in HERO:
        vals = {}
        for lab in labs:
            xs = [by_name[n][lab] for n in names if n in by_name and by_name[n][lab] is not None]
            vals[lab] = statistics.mean(xs) if xs else None
        if any(v is not None for v in vals.values()):
            clusters.append((title, vals, "ms"))
    clusters.append(("IDLE CPU", {l: extra[l]["cpu"] for l in labs}, "%"))
    clusters.append(("MEMORY", {l: (extra[l]["pss"] / 1024 if extra[l]["pss"] else None) for l in labs}, "MB"))
    pw, pg, cg, plot_h, left = 30, 6, 26, 250, 32
    cw = len(apps) * pw + (len(apps) - 1) * pg
    W = left * 2 + len(clusters) * cw + (len(clusters) - 1) * cg
    base = 110 + 22 + plot_h
    H = base + 76
    svg = frame(W, H, "FEELS INSTANT", "")
    svg[-1] = f'<text x="32" y="74" font-size="13" fill="{MUT}">{esc(res["meta"]["scenario"])} &#183; mean time until the screen is final &#183; lower is better &#183; each group scaled to its slowest</text>'
    for i, (title, vals, unit) in enumerate(clusters):
        x = left + i * (cw + cg)
        top_v = max((v for v in vals.values() if v), default=0)
        best = min((v for v in vals.values() if v is not None), default=None)
        svg.append(f'<rect x="{x}" y="{base}" width="{cw}" height="2" fill="{LINE}"/>')
        for j, (_, lab, col) in enumerate(apps):
            v = vals[lab]
            bx = x + j * (pw + pg)
            if v is None or not top_v:
                svg.append(f'<text x="{bx + pw / 2}" y="{base - 8}" font-size="10" font-weight="700" fill="{CORAL}" text-anchor="middle">n/a</text>')
                continue
            h = max(4, round(v / top_v * plot_h))
            svg.append(f'<rect x="{bx}" y="{base - h}" width="{pw}" height="{h}" fill="{col}"/>')
            isb = v == best
            svg.append(f'<text x="{bx + pw / 2}" y="{base - h - 7}" font-size="10" font-weight="{800 if isb else 400}" fill="{col if isb else MUT}" text-anchor="middle">{short(v, unit)}</text>')
        svg.append(f'<text x="{x + cw / 2}" y="{base + 22}" font-size="11" font-weight="700" fill="{FG}" text-anchor="middle">{title}</text>')
    legend(svg, apps, H - 20)
    svg.append("</svg>")
    return "\n".join(svg)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", nargs="?", help="run dir or results.json (default: latest in reports/)")
    ap.add_argument("-o", "--out", help="output dir (default: <run>/charts)")
    ap.add_argument("-m", "--metric", default="settled_ms", choices=["ready_ms", "first_byte_ms", "first_paint_ms", "settled_ms"])
    a = ap.parse_args()
    path, res = load(a.run)
    out = a.out or os.path.join(os.path.dirname(path), "charts")
    os.makedirs(out, exist_ok=True)
    apps, steps, extra = collect(res, a.metric)
    for name, svg in (("hero", chart_hero(res, apps, steps, extra, a.metric)), ("summary", chart_summary(res, apps, steps, extra, a.metric)), ("latency", chart_latency(res, apps, steps, a.metric))):
        p = os.path.join(out, f"{name}.svg")
        with open(p, "w", encoding="utf-8") as f:
            f.write(svg)
        print(p)


if __name__ == "__main__":
    main()
