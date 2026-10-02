#!/usr/bin/env python3
"""Draws the DABT-themed release charts (pixel-cell bars in the brand colours) as standalone SVGs.

    python3 tools/release_charts.py            # writes assets/release/devex-*-improvements.svg and *-pages.svg
    python3 tools/release_charts.py DIR        # same, into DIR

One entry per release in RELEASES; add the next release there. Numbers come from deep profiler runs (see
docs/design/performance-journey.md).
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "release")

BG, CARD, LINE = "#0b0f14", "#141c26", "#22303f"
FG, MUT = "#d7e0ea", "#8497ab"
PINK, BLUE, YELLOW, CORAL = "#ff8cbf", "#a8d8ff", "#fff3a8", "#ff9e9e"
FONT = "'JetBrains Mono',ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"

# (label, before, after, unit)  lower is better
RELEASES = [
    {
        "slug": "devex-1-75",
        "name": "DevEx Update 1.75",
        "improvements": [
            ("IDLE REPAINTS", 20.7, 2.0, "/s"),
            ("WHEEL SCROLL", 64.1, 17.3, "ms"),
            ("WARM START", 856.7, 287.0, "ms"),
            ("PALETTE CLOSE", 142.7, 51.6, "ms"),
            ("COLD START", 5836.0, 2901.0, "ms"),
            ("PAGE SWITCH, MEAN", 408.8, 202.7, "ms"),
            ("PAGE REVISIT", 370.4, 196.4, "ms"),
            ("PAGE FIRST VISIT", 355.5, 190.1, "ms"),
            ("MOUSE CLICK", 11.4, 10.0, "ms"),
            ("MOUSE HOVER", 9.45, 8.1, "ms"),
        ],
        # time spent starting processes (forks and external programs) per action, attributed from the trace
        "processes": [
            ("HOVER", 2.9, 0.0, "ms"),
            ("FOCUS (TAB)", 2.8, 0.0, "ms"),
            ("MOUSE CLICK", 12.3, 1.7, "ms"),
        ],
        "processes_title": "NO MORE PROCESSES ON INPUT",
        "processes_sub": "time spent starting processes per action",
        "improvements_sub": "lower is better &#183; bars show the new time as a share of the old",
        "pages": [  # page revisit, median ms
            ("components", 618, 260), ("docs", 532, 244), ("scrolling", 488, 314), ("monitor", 472, 274),
            ("settings", 372, 197), ("widgets", 364, 189), ("terminal", 358, 177), ("layout", 307, 145),
            ("home", 288, 149), ("case study", 283, 132),
        ],
        "pages_sub": "page switch on a revisit, median milliseconds &#183; first profiler run against the latest",
    },
    {
        "slug": "devex-1-87-5",
        "name": "DevEx Update 1.87,5",
        # deep runs 20260930-231054 (end of 1.75) against 20261001-201315
        "improvements": [
            ("PALETTE CLOSE", 51.6, 13.4, "ms"),
            ("SWITCH BY KEY (2 PAGES)", 229.3, 106.3, "ms"),
            ("TERMINAL RESIZE", 187.2, 144.3, "ms"),
            ("THEME SWITCH, FIRST", 270.3, 215.0, "ms"),
            ("PAGE REVISIT", 196.4, 156.4, "ms"),
            ("PAGE SWITCH, MEAN", 203.0, 173.0, "ms"),
            ("PAGE FIRST VISIT", 190.1, 184.4, "ms"),
        ],
        # forks per run of the demo callbacks that run on a visit, a tick or an input
        "processes": [
            ("MONITOR REFRESH", 20, 1, "forks"),
            ("COMPONENTS VISIT", 13, 0, "forks"),
            ("WIDGETS STATUS TICK", 5, 0, "forks"),
            ("DEBUG LAB TICK", 3, 0, "forks"),
        ],
        "processes_title": "NO MORE FORKS IN THE DEMO CALLBACKS",
        "processes_sub": "processes started per run of a callback on a visit, a tick or an input",
        "improvements_sub": "lower is better &#183; 1.75 against 1.87,5",
        "pages": [  # page revisit, median ms
            ("components", 260, 157), ("docs", 244, 214), ("scrolling", 314, 211), ("monitor", 274, 186),
            ("settings", 197, 146), ("widgets", 189, 147), ("terminal", 177, 153), ("layout", 145, 119),
            ("home", 149, 120), ("case study", 132, 109),
        ],
        "pages_sub": "page switch on a revisit, median milliseconds &#183; 1.75 against 1.87,5",
    },
    {
        "slug": "devex-1-93-75",
        "name": "DevEx Update 1.93,75",
        # floor: probe spans of the floor scenario, 20261001-211251 (the code of v0.0.21) -> deep run 20261001-230749;
        # page switches and switch by key: nav run 20261001-204153 (10 rounds, the build of v0.0.21) -> the same
        # interactions in the deep run 20261001-230749 (5 rounds, idle machine)
        "improvements": [
            ("TRIVIAL-PAGE SWITCH", 136.3, 86.5, "ms"),
            ("PAGE REVISIT", 152.1, 125.1, "ms"),
            ("PAGE SWITCH, MEAN", 165.1, 137.0, "ms"),
            ("PAGE FIRST VISIT", 180.3, 142.9, "ms"),
            ("SWITCH BY KEY (10 PAGES)", 124.0, 100.6, "ms"),
        ],
        # processes started per page switch (trace attribution, runs 20261001-204153 -> 212745)
        "processes": [
            ("STTY CALLS", 1, 0, "forks"),
        ],
        "processes_title": "NO MORE PROCESS ON A PAGE SWITCH",
        "processes_sub": "processes started per page switch: the terminal size is no longer read with stty",
        "improvements_sub": "lower is better &#183; v0.0.21 (1.87,5) against 1.93,75",
        "pages": [  # page revisit, median ms
            ("components", 153, 125), ("docs", 214, 188), ("scrolling", 162, 143), ("monitor", 179, 161),
            ("settings", 141, 121), ("widgets", 148, 124), ("terminal", 145, 129), ("layout", 114, 94),
            ("home", 117, 91), ("case study", 105, 86),
        ],
        "pages_title": "PAGE REVISIT, PER PAGE",
        "pages_sub": "page switch on a revisit, median milliseconds &#183; v0.0.21 against 1.93,75",
    },
    {
        "slug": "devex-2",
        "name": "DevEx Update 2",
        # held keys (new profiler groups, 30 presses per second): the same build without and with the focus work,
        # deep runs 20261002-222307 -> 20261002-223527. Work = app busy time per 1 s hold of the key.
        "improvements": [
            ("HELD UP/DOWN, NAV BAR: WORK", 478.0, 47.0, "ms"),
            ("HELD TAB: WORK", 420.0, 60.0, "ms"),
            ("HELD UP/DOWN, NAV BAR: LAG", 8.5, 4.5, "ms"),
            ("HELD TAB: LAG", 33.2, 21.2, "ms"),
        ],
        "processes": [
            ("NAV BAR HOLD", 49.5, 4.3, "KB"),
            ("TAB HOLD", 60.7, 15.9, "KB"),
        ],
        "processes_title": "FAR LESS PAINTED PER HELD KEY",
        "processes_sub": "bytes written to the terminal per hold: a focus move redraws only the two widgets that changed",
        "improvements_sub": "lower is better &#183; app work per hold and per-press lag, before and after the focus work",
        "pages": [  # per-press lag of a held key, median ms
            ("nav bar", 8.5, 4.5), ("tab", 33.2, 21.2), ("table", 7.3, 6.6), ("page keys", 4.8, 4.6),
            ("list", 4.5, 4.4), ("cursor", 2.7, 2.6), ("typing", 2.5, 4.3),
        ],
        "pages_title": "HELD KEY LAG, PER WIDGET",
        "pages_sub": "key sent to first output received, median milliseconds &#183; a held key repeats every 33 ms",
    },
]


def fmt(v, unit):
    if unit == "forks":
        return f"{v:g} forks" if v != 1 else "1 fork"
    if v == 0:
        return "0 ms"
    if unit == "/s":
        return f"{v:.1f}/s"
    if v >= 1000:
        return f"{v / 1000:.2f} s"
    return f"{v:.1f} ms" if v < 100 else f"{v:.0f} ms"


def cells(x, y, n, total, color, h, pitch=12, w=10, opacity=1.0):
    out = []
    for i in range(total):
        if i < n:
            out.append(f'<rect x="{x + i * pitch}" y="{y}" width="{w}" height="{h}" fill="{color}" opacity="{opacity}"/>')
    return "".join(out)


def frame(w, h, title, sub):
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" shape-rendering="crispEdges" font-family="{FONT}">',
        f'<rect width="{w}" height="{h}" fill="{BG}"/>',
        f'<rect x="1" y="1" width="{w - 2}" height="{h - 2}" fill="{CARD}" stroke="{LINE}" stroke-width="2"/>',
        f'<rect x="1" y="1" width="{w - 2}" height="6" fill="{PINK}"/>',
        f'<rect x="{w // 3}" y="1" width="{w // 3}" height="6" fill="{BLUE}"/>',
        f'<rect x="{2 * w // 3}" y="1" width="{w // 3 - 1}" height="6" fill="{YELLOW}"/>',
        f'<text x="32" y="50" font-size="22" font-weight="700" fill="{FG}">{title}</text>',
        f'<text x="32" y="74" font-size="13" fill="{MUT}">{sub}</text>',
    ]


def rows(svg, items, x0, top, row, N, label_w=32):
    for i, (label, a, b, unit) in enumerate(items):
        y = top + i * row
        n_after = 0 if b == 0 else max(1, round(b / a * N))
        svg.append(f'<text x="{label_w}" y="{y + 19}" font-size="13" font-weight="700" fill="{FG}">{label}</text>')
        svg.append(cells(x0, y + 2, N, N, BLUE, 11, opacity=0.35))
        svg.append(cells(x0, y + 18, n_after, N, PINK, 14))
        svg.append(f'<text x="{x0 + N * 12 + 16}" y="{y + 13}" font-size="12" fill="{MUT}">{fmt(a, unit)}</text>')
        svg.append(f'<text x="{x0 + N * 12 + 16}" y="{y + 31}" font-size="14" font-weight="700" fill="{PINK}">{fmt(b, unit)}</text>')
        pct = round((b - a) / a * 100)
        bx = x0 + N * 12 + 110
        svg.append(f'<rect x="{bx}" y="{y + 4}" width="70" height="26" fill="{YELLOW}"/>')
        svg.append(f'<text x="{bx + 35}" y="{y + 22}" font-size="14" font-weight="800" fill="{BG}" text-anchor="middle">&#8722;{abs(pct)}%</text>')


def chart_improvements(cfg):
    W, row, top, N = 980, 54, 104, 44
    x0 = 232
    sec_gap = 74
    IMPROVEMENTS, PROCESSES = cfg["improvements"], cfg["processes"]
    H = top + row * len(IMPROVEMENTS) + sec_gap + row * len(PROCESSES) + 64
    svg = frame(W, H, "BEFORE &#8594; AFTER", f"D.A.B.T {cfg['name']} &#183; {cfg['improvements_sub']}")
    rows(svg, IMPROVEMENTS, x0, top, row, N)
    y2 = top + row * len(IMPROVEMENTS) + 8
    svg.append(f'<rect x="32" y="{y2}" width="{W - 64}" height="2" fill="{LINE}"/>')
    svg.append(f'<text x="32" y="{y2 + 30}" font-size="15" font-weight="700" fill="{YELLOW}">{cfg["processes_title"]}</text>')
    svg.append(f'<text x="32" y="{y2 + 50}" font-size="12" fill="{MUT}">{cfg["processes_sub"]}</text>')
    rows(svg, PROCESSES, x0, y2 + 60, row, N)
    ly = H - 30
    svg.append(f'<rect x="32" y="{ly - 10}" width="14" height="10" fill="{BLUE}" opacity="0.35"/><text x="54" y="{ly}" font-size="12" fill="{MUT}">before</text>')
    svg.append(f'<rect x="128" y="{ly - 10}" width="14" height="10" fill="{PINK}"/><text x="150" y="{ly}" font-size="12" fill="{MUT}">after</text>')
    svg.append("</svg>")
    return "\n".join(svg)


def chart_pages(cfg):
    W, row, top, N = 980, 38, 104, 44
    PAGES = cfg["pages"]
    H = top + row * len(PAGES) + 64
    svg = frame(W, H, cfg.get("pages_title", "EVERY PAGE, FASTER"), cfg["pages_sub"])
    x0 = 160
    scale = max(a for _, a, _ in PAGES) / N
    for i, (name, a, b) in enumerate(PAGES):
        y = top + i * row
        na, nb = max(1, round(a / scale)), max(1, round(b / scale))
        svg.append(f'<text x="32" y="{y + 18}" font-size="13" font-weight="700" fill="{FG}">{name.upper()}</text>')
        svg.append(cells(x0, y + 1, na, N, BLUE, 9, opacity=0.35))
        svg.append(cells(x0, y + 13, nb, N, PINK, 11))
        svg.append(f'<text x="{x0 + N * 12 + 16}" y="{y + 19}" font-size="13" fill="{MUT}">{a} &#8594; <tspan fill="{PINK}" font-weight="700">{b} ms</tspan></text>')
    ly = H - 30
    svg.append(f'<rect x="32" y="{ly - 10}" width="14" height="10" fill="{BLUE}" opacity="0.35"/><text x="54" y="{ly}" font-size="12" fill="{MUT}">before</text>')
    svg.append(f'<rect x="128" y="{ly - 10}" width="14" height="10" fill="{PINK}"/><text x="150" y="{ly}" font-size="12" fill="{MUT}">after</text>')
    svg.append("</svg>")
    return "\n".join(svg)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    os.makedirs(out, exist_ok=True)
    for cfg in RELEASES:
        for suffix, fn in (("improvements", chart_improvements), ("pages", chart_pages)):
            path = os.path.join(out, f"{cfg['slug']}-{suffix}.svg")
            open(path, "w", encoding="utf-8").write(fn(cfg))
            print(os.path.relpath(path, REPO))


if __name__ == "__main__":
    main()
