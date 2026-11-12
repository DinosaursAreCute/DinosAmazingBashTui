#!/usr/bin/env python3
"""Radar ("spider web") chart of every tested interaction area, the frameworks overlaid, mean time per framework below.

    python3 chart_all.py                       # latest run in reports/ -> all.svg in the current directory
    python3 chart_all.py RUN_DIR|results.json [-o FILE] [-m ready_ms|first_byte_ms|first_paint_ms|settled_ms]

One spoke per interaction area (the steps of a prefix, e.g. table.*, grouped; the spoke value is their mean). Radius is
a log scale of milliseconds: the centre is fastest, the outer ring slowest. The table under the chart gives each
framework's mean per interaction area. Stdlib only; colours and loading come from charts.py.
"""
import argparse
import math
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import charts as C  # noqa: E402

W, H0 = 960, 1000
CX, CY, R = W // 2, 440, 270
AREAS = {  # only the interactions anyone can picture, in plain words; page-specific steps (forms, tabs, jobs...) stay out
    "startup": "Start the app", "nav": "Switch page", "revisit": "Go back to a page", "dialog": "Open a dialog",
    "palette": "Command palette", "theme": "Switch theme", "resize": "Resize the window",
}


def ms(v):
    return C.fmt_ms(v).replace(" ", "")


def build(res, metric):
    apps, steps, _ = C.collect(res, metric)
    areas = {}  # area -> app label -> [step medians]
    for name, row in steps:
        a = areas.setdefault(name.split(".")[0], {lab: [] for _, lab, _ in apps})
        for lab, v in row.items():
            if v:
                a[lab].append(v)
    keys = [k for k in areas if k in AREAS]
    val = {k: {lab: statistics.mean(v) if v else None for lab, v in areas[k].items()} for k in keys}
    allv = [v for k in keys for v in val[k].values() if v]
    lo = 10 ** math.floor(math.log10(min(allv)))
    hi = 10 ** math.ceil(math.log10(max(allv)))
    rad = lambda v: R * 0.06 + (R * 0.94) * (math.log10(v) - math.log10(lo)) / (math.log10(hi) - math.log10(lo))
    ang = lambda i: -math.pi / 2 + 2 * math.pi * i / len(keys)
    pt = lambda i, r: (CX + r * math.cos(ang(i)), CY + r * math.sin(ang(i)))

    o = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H0}" viewBox="0 0 {W} {H0}" font-family="{C.FONT}">',
        f'<rect width="{W}" height="{H0}" fill="{C.BG}"/>',
        f'<rect x="1" y="1" width="{W - 2}" height="{H0 - 2}" fill="{C.CARD}" stroke="{C.LINE}" stroke-width="2"/>',
        f'<text x="32" y="52" font-size="22" font-weight="700" fill="{C.FG}">EVERY INTERACTION</text>',
        f'<text x="32" y="76" font-size="13" fill="{C.MUT}">How long each action takes until the screen has finished updating '
        f'&#183; closer to the centre is faster</text>',
    ]
    lx = 32
    for _, lab, col in apps:
        o.append(f'<rect x="{lx}" y="96" width="14" height="10" fill="{col}"/><text x="{lx + 22}" y="106" font-size="12" fill="{C.MUT}">{C.esc(lab)}</text>')
        lx += 50 + 8 * len(lab)

    t = lo  # rings: one per decade, labelled up the top spoke
    while t <= hi * 1.0001:
        r = rad(t)
        ring = " ".join(f"{pt(i, r)[0]:.1f},{pt(i, r)[1]:.1f}" for i in range(len(keys)))
        o.append(f'<polygon points="{ring}" fill="none" stroke="{C.LINE}" stroke-width="1"/>')
        tick = f"{t / 1000:g}s" if t >= 1000 else f"{t:g}ms"
        o.append(f'<text x="{CX + 6}" y="{CY - r + 14:.1f}" font-size="10" fill="{C.MUT}" stroke="{C.CARD}" stroke-width="3" paint-order="stroke">{tick}</text>')
        t *= 10
    for i, k in enumerate(keys):
        x, y = pt(i, R)
        o.append(f'<line x1="{CX}" y1="{CY}" x2="{x:.1f}" y2="{y:.1f}" stroke="{C.LINE}" stroke-width="1"/>')
        lx, ly = pt(i, R + 18)
        c = math.cos(ang(i))
        anchor = "middle" if abs(c) < 0.2 else ("start" if c > 0 else "end")
        o.append(f'<text x="{lx:.1f}" y="{ly + 4:.1f}" font-size="12" font-weight="700" fill="{C.FG}" text-anchor="{anchor}">{AREAS.get(k, k.title())}</text>')

    for _, lab, col in reversed(apps):  # first app on top
        pts = [(i, val[k][lab]) for i, k in enumerate(keys) if val[k][lab]]
        poly = " ".join(f"{pt(i, rad(v))[0]:.1f},{pt(i, rad(v))[1]:.1f}" for i, v in pts)
        o.append(f'<polygon points="{poly}" fill="{col}" fill-opacity="0.13" stroke="{col}" stroke-width="2.5" stroke-linejoin="round"/>')
        for i, v in pts:
            x, y = pt(i, rad(v))
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4" fill="{col}"><title>{C.esc(lab)} &#183; {AREAS.get(keys[i], keys[i])}: {ms(v)}</title></circle>')

    y0 = 800
    colx = [330, 530, 730]  # right edge of each framework column
    o.append(f'<text x="32" y="{y0 - 20}" font-size="12" fill="{C.MUT}">MEAN TIME PER INTERACTION &#183; mean of the steps in each area &#183; fastest in each row is bold</text>')
    for (_, lab, col), x in zip(apps, colx):
        o.append(f'<rect x="{x - 8 * len(lab) - 22}" y="{y0 - 2}" width="14" height="10" fill="{col}"/><text x="{x}" y="{y0 + 8}" font-size="12" font-weight="700" fill="{col}" text-anchor="end">{C.esc(lab)}</text>')
    o.append(f'<rect x="32" y="{y0 + 16}" width="{W - 64}" height="1" fill="{C.LINE}"/>')
    ry = y0 + 40
    for n, k in enumerate(keys):
        if n % 2:
            o.append(f'<rect x="24" y="{ry - 15}" width="{W - 48}" height="22" fill="#ffffff" opacity="0.025"/>')
        o.append(f'<text x="32" y="{ry}" font-size="12" fill="{C.FG}">{AREAS.get(k, k.title())}</text>')
        o.append(f'<text x="{W - 32}" y="{ry}" font-size="11" fill="{C.MUT}" text-anchor="end">{len(areas[k][apps[0][1]])} steps</text>')
        row = {lab: val[k][lab] for _, lab, _ in apps}
        best = min((v for v in row.values() if v), default=None)
        for (_, lab, col), x in zip(apps, colx):
            v = row[lab]
            if not v:
                continue
            win = v == best
            o.append(f'<text x="{x}" y="{ry}" font-size="12" font-weight="{800 if win else 400}" fill="{col if win else C.MUT}" text-anchor="end">{ms(v)}</text>')
        ry += 22

    o[0] = o[0].replace(f'height="{H0}"', f'height="{ry + 12}"').replace(f'0 0 {W} {H0}', f'0 0 {W} {ry + 12}')
    o[1] = o[1].replace(f'height="{H0}"', f'height="{ry + 12}"')
    o[2] = o[2].replace(f'height="{H0 - 2}"', f'height="{ry + 10}"')
    o.append("</svg>")
    return "\n".join(o)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run", nargs="?")
    ap.add_argument("-o", "--out", default="all.svg")
    ap.add_argument("-m", "--metric", default="ready_ms", choices=["ready_ms", "first_byte_ms", "first_paint_ms", "settled_ms"])
    a = ap.parse_args()
    _, res = C.load(a.run)
    with open(a.out, "w") as f:
        f.write(build(res, a.metric))
    print(os.path.abspath(a.out))


if __name__ == "__main__":
    main()
