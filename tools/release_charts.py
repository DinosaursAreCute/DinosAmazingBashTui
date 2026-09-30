#!/usr/bin/env python3
"""Draws the DABT-themed release charts (pixel-cell bars in the brand colours) as standalone SVGs.

    python3 tools/release_charts.py            # writes assets/release/devex-1-75-*.svg

Numbers: first deep profiler run against the latest deep run (see docs/design/performance-journey.md);
update the tables below for the next release.
"""
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "release")

BG, CARD, LINE = "#0b0f14", "#141c26", "#22303f"
FG, MUT = "#d7e0ea", "#8497ab"
PINK, BLUE, YELLOW, CORAL = "#ff8cbf", "#a8d8ff", "#fff3a8", "#ff9e9e"
FONT = "'JetBrains Mono',ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"

# (label, before, after, unit)  lower is better
IMPROVEMENTS = [
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
]
# time spent starting processes (forks and external programs) per action, attributed from the trace
PROCESSES = [
    ("HOVER", 2.9, 0.0, "ms"),
    ("FOCUS (TAB)", 2.8, 0.0, "ms"),
    ("MOUSE CLICK", 12.3, 1.7, "ms"),
]
PAGES = [  # page revisit, median ms
    ("components", 618, 260), ("docs", 532, 244), ("scrolling", 488, 314), ("monitor", 472, 274),
    ("settings", 372, 197), ("widgets", 364, 189), ("terminal", 358, 177), ("layout", 307, 145),
    ("home", 288, 149), ("case study", 283, 132),
]


def fmt(v, unit):
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


def chart_improvements():
    W, row, top, N = 980, 54, 104, 44
    x0 = 232
    sec_gap = 74
    H = top + row * len(IMPROVEMENTS) + sec_gap + row * len(PROCESSES) + 64
    svg = frame(W, H, "BEFORE &#8594; AFTER", "D.A.B.T DevEx Update 1.75 &#183; lower is better &#183; bars show the new time as a share of the old")
    rows(svg, IMPROVEMENTS, x0, top, row, N)
    y2 = top + row * len(IMPROVEMENTS) + 8
    svg.append(f'<rect x="32" y="{y2}" width="{W - 64}" height="2" fill="{LINE}"/>')
    svg.append(f'<text x="32" y="{y2 + 30}" font-size="15" font-weight="700" fill="{YELLOW}">NO MORE PROCESSES ON INPUT</text>')
    svg.append(f'<text x="32" y="{y2 + 50}" font-size="12" fill="{MUT}">time spent starting processes per action</text>')
    rows(svg, PROCESSES, x0, y2 + 60, row, N)
    ly = H - 30
    svg.append(f'<rect x="32" y="{ly - 10}" width="14" height="10" fill="{BLUE}" opacity="0.35"/><text x="54" y="{ly}" font-size="12" fill="{MUT}">before</text>')
    svg.append(f'<rect x="128" y="{ly - 10}" width="14" height="10" fill="{PINK}"/><text x="150" y="{ly}" font-size="12" fill="{MUT}">after</text>')
    svg.append("</svg>")
    return "\n".join(svg)


def chart_pages():
    W, row, top, N = 980, 38, 104, 44
    H = top + row * len(PAGES) + 64
    svg = frame(W, H, "EVERY PAGE, FASTER", "page switch on a revisit, median milliseconds &#183; first profiler run against the latest")
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
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("devex-1-75-improvements.svg", chart_improvements), ("devex-1-75-pages.svg", chart_pages)):
        path = os.path.join(OUT, name)
        open(path, "w", encoding="utf-8").write(fn())
        print(os.path.relpath(path, REPO))


if __name__ == "__main__":
    main()
