#!/usr/bin/env python3
"""screenshots.py - PNG screenshot of every DABT demo page under every theme (headless, no terminal needed).
  tools/debug/screenshots.py [-o OUTDIR] [-r ROWSxCOLS] [-t THEME,...] [-p PAGE|PAGE@TAB|PAGE@*,...] [--settle SEC] [-j JOBS] [--font PATH] [--size PX]
Runs screenshot_driver.sh once per theme (frames are dumped via tui.render), then rasterises the ANSI frame with a
small built-in VT emulator + Pillow. Output: OUTDIR/<ROWSxCOLS>/<theme>/<page>.png (-r takes a comma list, default 45x150,70x280) (default OUTDIR: tools/debug/screenshots/).
Each shot waits --settle seconds (default 0.5) with timers polled, so clocks/jobs have content. Live content (tui.exec, timers) is not running headless, so those panes show their initial state.
"""
import argparse, multiprocessing, glob, os, re, subprocess, sys, tempfile
from concurrent.futures import ProcessPoolExecutor
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.normpath(os.path.join(HERE, '..', '..', 'share', 'demo'))
DEF_FG, DEF_BG = (192, 202, 245), (26, 27, 38)
BASE16 = [(0,0,0),(205,49,49),(13,188,121),(229,229,16),(36,114,200),(188,63,188),(17,168,205),(229,229,229),
          (102,102,102),(241,76,76),(35,209,139),(245,245,67),(59,142,234),(214,112,214),(41,184,219),(255,255,255)]

def c256(n):
    if n < 16: return BASE16[n]
    if n >= 232: v = 8 + (n - 232) * 10; return (v, v, v)
    n -= 16; lv = [0, 95, 135, 175, 215, 255]; return (lv[n // 36], lv[n // 6 % 6], lv[n % 6])

class Screen:
    def __init__(s, rows, cols):
        s.rows, s.cols = rows, cols; s.wrap = True; s.r = s.c = 0; s.saved = (0, 0)
        s.reset_attr(); s.g = [[(' ', None, None, 0)] * cols for _ in range(rows)]
    def reset_attr(s): s.fg = s.bg = None; s.mod = 0
    def put(s, ch):
        if s.c >= s.cols:
            if s.wrap: s.c = 0; s.r = min(s.r + 1, s.rows - 1)
            else: s.c = s.cols - 1
        s.g[s.r][s.c] = (ch, s.fg, s.bg, s.mod); s.c += 1
    def sgr(s, ps):
        ps = [int(x) if x.isdigit() else 0 for x in ps.split(';')] if ps else [0]; i = 0
        while i < len(ps):
            p = ps[i]
            if p == 0: s.reset_attr()
            elif p in (1, 2, 3, 4, 7, 9): s.mod |= 1 << p
            elif p in (22, 23, 24, 27, 29): s.mod &= ~(1 << {22: 1, 23: 3, 24: 4, 27: 7, 29: 9}[p]); s.mod &= ~((p == 22) << 2)
            elif 30 <= p <= 37: s.fg = BASE16[p - 30]
            elif 90 <= p <= 97: s.fg = BASE16[p - 90 + 8]
            elif 40 <= p <= 47: s.bg = BASE16[p - 40]
            elif 100 <= p <= 107: s.bg = BASE16[p - 100 + 8]
            elif p == 39: s.fg = None
            elif p == 49: s.bg = None
            elif p in (38, 48):
                if i + 1 < len(ps) and ps[i + 1] == 2 and i + 4 < len(ps): col = tuple(ps[i + 2:i + 5]); i += 4
                elif i + 1 < len(ps) and ps[i + 1] == 5 and i + 2 < len(ps): col = c256(ps[i + 2]); i += 2
                else: col = None
                if col: (setattr(s, 'fg', col) if p == 38 else setattr(s, 'bg', col))
            i += 1
    def feed(s, data):
        for m in re.finditer(r'\x1b\[([?0-9;]*)([@-~])|\x1b\](?:.*?)(?:\x07|\x1b\\)|\x1b([78])|\x1b[()][A-Za-z0-9]|([^\x1b]+)|\x1b', data, re.S):
            if m.group(4):
                for ch in m.group(4):
                    if ch == '\n': s.r = min(s.r + 1, s.rows - 1)
                    elif ch == '\r': s.c = 0
                    elif ch >= ' ': s.put(ch)
                continue
            if m.group(3): s.saved, = [(s.r, s.c)] if m.group(3) == '7' else [s.saved]; (s.__setattr__('r', s.saved[0]), s.__setattr__('c', s.saved[1])) if m.group(3) == '8' else None; continue
            args, f = m.group(1), m.group(2)
            if args in ('?7',) and f in 'lh': s.wrap = f == 'h'
            if args is None or args.startswith('?'): continue
            n = [int(x) if x else 0 for x in args.split(';')] if args else []
            a = n[0] if n and n[0] else 1
            if f in 'Hf': s.r = min(max((n[0] if n and n[0] else 1) - 1, 0), s.rows - 1); s.c = min(max((n[1] if len(n) > 1 and n[1] else 1) - 1, 0), s.cols - 1)
            elif f == 'A': s.r = max(s.r - a, 0)
            elif f == 'B': s.r = min(s.r + a, s.rows - 1)
            elif f == 'C': s.c = min(s.c + a, s.cols - 1)
            elif f == 'D': s.c = max(s.c - a, 0)
            elif f == 'G': s.c = min(a - 1, s.cols - 1)
            elif f == 'd': s.r = min(a - 1, s.rows - 1)
            elif f == 'K':
                lo, hi = (s.c, s.cols) if not n or n[0] == 0 else ((0, s.c + 1) if n[0] == 1 else (0, s.cols))
                for x in range(lo, hi): s.g[s.r][x] = (' ', None, s.bg, 0)
            elif f == 'X':
                for x in range(s.c, min(s.c + a, s.cols)): s.g[s.r][x] = (' ', None, s.bg, 0)
            elif f == 'J' and n and n[0] in (2, 3):
                s.g = [[(' ', None, s.bg, 0)] * s.cols for _ in range(s.rows)]
            elif f == 'm': s.sgr(args)

def render(scr, font, bold, cw, ch, asc, path):
    img = Image.new('RGB', (scr.cols * cw, scr.rows * ch), DEF_BG); d = ImageDraw.Draw(img)
    for y, row in enumerate(scr.g):
        for x, (t, fg, bg, mod) in enumerate(row):
            f, b = fg or DEF_FG, bg or DEF_BG
            if mod & 2: f = tuple(int(v * .6 + q * .4) for v, q in zip(f, b))
            if mod & 128: f, b = b, f
            if b != DEF_BG: d.rectangle([x * cw, y * ch, (x + 1) * cw - 1, (y + 1) * ch - 1], fill=b)
            if t != ' ':
                d.text((x * cw, y * ch + asc), t, font=bold if mod & 2 ** 1 else font, fill=f, anchor='ls')
            if mod & 16: d.line([x * cw, (y + 1) * ch - 2, (x + 1) * cw, (y + 1) * ch - 2], fill=f)
    img.save(path)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('-o', default=os.path.join(HERE, 'screenshots'))
    ap.add_argument('-r', default='45x150,70x280'); ap.add_argument('-t'); ap.add_argument('-p')
    ap.add_argument('--settle', default='0.5'); ap.add_argument('-j', type=int, default=os.cpu_count() or 4, help='parallel jobs (default: CPU count)'); ap.add_argument('--font'); ap.add_argument('--size', type=int, default=16); a = ap.parse_args()
    themes = a.t.split(',') if a.t else ['default'] + sorted(os.path.basename(f)[:-4] for f in glob.glob(PAGES + '/themes/*.css'))
    extra = ['case_study@tab_tbl', 'docu@*']          # tabs worth their own shot (tab pages of components/debug are real pages already)
    pages = a.p.split(',') if a.p else extra + sorted(os.path.basename(f)[:-4] for f in glob.glob(PAGES + '/*.xml')
                                               if not os.path.basename(f).startswith('_') and os.path.basename(f) != 'commands.xml')
    fpath = a.font or next((p for p in glob.glob('/usr/share/fonts/**/JetBrainsMono*NerdFontMono-Regular.ttf', recursive=True)
                            + glob.glob('/usr/share/fonts/**/JetBrainsMonoNerdFont-Regular.ttf', recursive=True)
                            + glob.glob('/usr/share/fonts/**/DejaVuSansMono.ttf', recursive=True)), None)
    if not fpath: sys.exit('no monospace font found, pass --font')
    jobs = [(size, th, [pg], a.o, a.settle, fpath, a.size) for size in a.r.split(",") for th in themes for pg in pages]
    with ProcessPoolExecutor(max_workers=a.j) as ex:          # one (size, theme, page) per worker: bash driver + rasterising
        for lines in ex.map(job, jobs):
            for l in lines: print(l)

def job(j):
    size, th, pages, out, settle, fpath, px = j
    rows, cols = map(int, size.split('x')); done = []
    font = ImageFont.truetype(fpath, px); bpath = fpath.replace('Regular', 'Bold'); bold = ImageFont.truetype(bpath if os.path.exists(bpath) else fpath, px)
    cw = round(font.getlength('M')); asc, desc = font.getmetrics(); ch = asc + desc
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(['env', 'SETTLE=' + settle, 'bash', os.path.join(HERE, 'screenshot_driver.sh'), th, size, tmp, PAGES, *pages],
                       check=False, timeout=600, stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.makedirs(os.path.join(out, size, th), exist_ok=True)
        for src in sorted(glob.glob(tmp + '/*.ans')):
            p = os.path.basename(src)[:-4]
            scr = Screen(rows, cols); scr.feed(open(src, encoding='utf-8', errors='replace').read())
            render(scr, font, bold, cw, ch, asc, os.path.join(out, size, th, p + '.png')); done.append(f'  {size}/{th}/{p}.png')
    return done

if __name__ == '__main__': main()
