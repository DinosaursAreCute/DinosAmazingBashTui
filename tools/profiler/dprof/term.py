"""ANSI toolkit: colours, bars, sparklines, panels. No dependencies; degrades to plain text."""
import os
import re
import shutil
import sys

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
USE_COLOR = True

PAL = {
    "text": (201, 209, 224), "dim": (120, 129, 150), "faint": (78, 86, 105), "line": (58, 65, 84),
    "cyan": (86, 214, 220), "blue": (97, 175, 239), "purple": (198, 120, 221), "green": (126, 211, 130),
    "yellow": (235, 200, 110), "orange": (232, 150, 90), "red": (240, 95, 110), "pink": (240, 130, 180),
    "teal": (80, 200, 170), "white": (240, 244, 250),
}
RATING_COLOR = {"good": "green", "ok": "yellow", "slow": "red", "na": "dim"}
LAYER_COLOR = {
    "input": "blue", "loop": "dim", "focus": "pink", "scroll": "teal", "markup": "purple", "cache": "orange",
    "style": "yellow", "layout": "cyan", "render": "green", "flush": "teal", "widgets": "pink", "chrome": "blue",
    "term": "orange", "diag": "faint", "plugin": "purple", "config": "yellow", "core": "dim", "app": "white", "process": "red",
}
BLOCKS = " ▏▎▍▌▋▊▉█"
SPARKS = "▁▂▃▄▅▆▇█"


def set_color(on):
    global USE_COLOR
    USE_COLOR = on


def width(default=120):
    try:
        return max(80, min(shutil.get_terminal_size((default, 40)).columns, 170))
    except OSError:
        return default


def rgb(name):
    return PAL[name] if isinstance(name, str) else name


def c(text, fg=None, bold=False, dim=False, bg=None, italic=False):
    if not USE_COLOR:
        return str(text)
    codes = []
    if bold:
        codes.append("1")
    if dim:
        codes.append("2")
    if italic:
        codes.append("3")
    if fg is not None:
        r, g, b = rgb(fg)
        codes.append(f"38;2;{r};{g};{b}")
    if bg is not None:
        r, g, b = rgb(bg)
        codes.append(f"48;2;{r};{g};{b}")
    return f"\x1b[{';'.join(codes)}m{text}\x1b[0m" if codes else str(text)


def vlen(s):
    s = ANSI_RE.sub("", s)
    return sum(2 if _wide(ch) else 1 for ch in s)


def _wide(ch):
    o = ord(ch)
    return 0x1100 <= o <= 0x115F or 0x2E80 <= o <= 0xA4CF or 0xAC00 <= o <= 0xD7A3 or 0xF900 <= o <= 0xFAFF \
        or 0xFE30 <= o <= 0xFE6F or 0xFF00 <= o <= 0xFF60 or 0x1F300 <= o <= 0x1FAFF


def pad(s, w, align="l"):
    n = w - vlen(s)
    if n <= 0:
        return clip(s, w)
    return s + " " * n if align == "l" else " " * n + s if align == "r" else " " * (n // 2) + s + " " * (n - n // 2)


def clip(s, w):
    if vlen(s) <= w:
        return s
    out, n, i = [], 0, 0
    while i < len(s) and n < w - 1:
        m = ANSI_RE.match(s, i)
        if m:
            out.append(m.group())
            i = m.end()
            continue
        out.append(s[i])
        n += 1
        i += 1
    return "".join(out) + ("…\x1b[0m" if USE_COLOR else "…")


def bar(frac, w, fg="green", bg="line"):
    """Horizontal bar with 1/8-cell resolution."""
    frac = max(0.0, min(1.0, frac))
    cells = frac * w
    full = int(cells)
    part = int((cells - full) * 8)
    s = "█" * full + (BLOCKS[part] if part and full < w else "")
    s = s.ljust(w)[:w] if not USE_COLOR else s
    if not USE_COLOR:
        return s.replace(" ", "·")
    rest = w - vlen(s)
    return c(s, fg) + c("░" * rest, bg) if rest > 0 else c(s, fg)


def stacked(parts, w):
    """parts: [(frac, color)] -> one bar of total width w."""
    total = sum(f for f, _ in parts) or 1.0
    cells, acc, out = [], 0.0, []
    used = 0
    for i, (f, col) in enumerate(parts):
        acc += f / total * w
        n = int(round(acc)) - used
        if i == len(parts) - 1:
            n = w - used
        if n > 0:
            out.append(c("█" * n, col))
            used += n
    return "".join(out) if USE_COLOR else "█" * w


def spark(vals, w=None, fg="cyan"):
    vals = [v for v in vals if v is not None]
    if not vals:
        return ""
    if w and len(vals) > w:
        step = len(vals) / w
        vals = [sum(vals[int(i * step):max(int(i * step) + 1, int((i + 1) * step))]) / max(1, len(vals[int(i * step):max(int(i * step) + 1, int((i + 1) * step))])) for i in range(w)]
    lo, hi = min(vals), max(vals)
    span = (hi - lo) or 1.0
    return c("".join(SPARKS[min(7, int((v - lo) / span * 7.999))] for v in vals), fg)


def heat(frac):
    """0..1 -> colour from deep blue-grey through amber to red."""
    frac = max(0.0, min(1.0, frac))
    stops = [(0.0, (48, 56, 76)), (0.25, (70, 110, 150)), (0.5, (220, 190, 100)), (0.75, (236, 140, 80)), (1.0, (240, 85, 100))]
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if frac <= b:
            t = (frac - a) / (b - a)
            return tuple(int(ca[i] + (cb[i] - ca[i]) * t) for i in range(3))
    return stops[-1][1]


def fmt_ms(v, digits=None):
    if v is None:
        return "–"
    if v >= 10000:
        return f"{v / 1000:.1f} s"
    if v >= 1000:
        return f"{v / 1000:.2f} s"
    if v >= 100:
        return f"{v:.0f} ms"
    if v >= 10:
        return f"{v:.1f} ms"
    if v >= 0.1:
        return f"{v:.2f} ms"
    return f"{v * 1000:.0f} µs"


def fmt_bytes(v):
    if v is None:
        return "–"
    if v >= 1 << 20:
        return f"{v / (1 << 20):.1f} MB"
    if v >= 1024:
        return f"{v / 1024:.1f} KB"
    return f"{v:.0f} B"


def fmt_num(v):
    if v is None:
        return "–"
    if v >= 1e6:
        return f"{v / 1e6:.1f}M"
    if v >= 1e4:
        return f"{v / 1e3:.0f}k"
    if v >= 100:
        return f"{v:.0f}"
    if v >= 10:
        return f"{v:.1f}"
    return f"{v:.2f}".rstrip("0").rstrip(".")


def hline(w, fg="line", ch="─"):
    return c(ch * w, fg)


def panel(title, lines, w, accent="cyan", subtitle=""):
    """Rounded box with a title in the top edge."""
    inner = w - 4
    t = f" {c(title, accent, bold=True)} " if title else ""
    sub = f" {c(subtitle, 'dim')} " if subtitle else ""
    top_fill = w - 2 - vlen(t) - vlen(sub) - 1
    out = [c("╭─", "line") + t + c("─" * max(0, top_fill), "line") + sub + c("╮", "line")]
    for ln in lines:
        out.append(c("│ ", "line") + pad(ln, inner) + c(" │", "line"))
    out.append(c("╰" + "─" * (w - 2) + "╯", "line"))
    return out


def side_by_side(left, right, wl, wr, gap=2):
    n = max(len(left), len(right))
    left = left + [""] * (n - len(left))
    right = right + [""] * (n - len(right))
    return [pad(a, wl) + " " * gap + pad(b, wr) for a, b in zip(left, right)]


def is_tty():
    return sys.stdout.isatty()


def init(force_color=None):
    on = is_tty() and "NO_COLOR" not in os.environ
    if force_color is not None:
        on = force_color
    set_color(on)
    return on
