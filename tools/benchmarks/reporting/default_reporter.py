"""The default terminal report for any benchmark that produces the profiler's results shape (see reporting/README.md):
a header, a scorecard of groups rated against budgets, per-group case tables and a diff against the previous run.
The DABT profiler adds its own panels on top of these pieces; a new benchmark only needs `render(report)`."""
from . import term
from .term import c, pad, vlen, bar, spark, fmt_ms, fmt_bytes, fmt_num, panel, RATING_COLOR
from .stats import NOISY_CORES

GLYPH = {"good": "●", "ok": "●", "slow": "●", "na": "○"}


def _chip(text, color, dark=True):
    if not term.USE_COLOR:
        return f"[{text}]"
    return c(f" {text} ", (20, 22, 30) if dark else "white", bold=True, bg=color)


def _cell(text, frac, w):
    r, g, b = term.heat(frac)
    fg = (20, 22, 30) if (r * 0.3 + g * 0.6 + b * 0.1) > 120 else (235, 240, 250)
    return c(pad(text, w, "r"), fg, bg=(r, g, b)) if term.USE_COLOR else pad(text, w, "r")


def _meter(value, budget, w):
    """0 .. 2x budget; the tick marks the budget itself."""
    if value is None or not budget:
        return " " * w
    frac = min(1.0, value / (2 * budget))
    rating = "good" if value <= budget else "ok" if value <= 2 * budget else "slow"
    filled = int(round(frac * w))
    mid = w // 2
    cells = []
    for i in range(w):
        if i < filled:
            cells.append(c("█", RATING_COLOR[rating]))
        elif i == mid:
            cells.append(c("┃", "dim"))
        else:
            cells.append(c("░", "line"))
    return "".join(cells) if term.USE_COLOR else "".join("█" if i < filled else ("|" if i == mid else ".") for i in range(w))


def _tile(title, value, sub, color, frac, w):
    lines = [c(title, "dim"), c(value, color, bold=True), bar(frac, w - 4, color), c(sub, "dim")]
    return panel("", lines, w, accent=color)


def header(rep, W, title=None):
    m = rep["meta"]
    left = f" {c('◆', 'cyan', bold=True)} {c(title or m.get('title') or 'BENCHMARK', 'white', bold=True)}  " \
           f"{c(m.get('commit', ''), 'purple')} {c(m.get('branch', ''), 'dim')}" \
           f"{c(' · dirty' if m.get('dirty') else '', 'orange')}"
    scn = "" if m.get("scenario", "full") == "full" else f"scenario {m['scenario']} · "
    parts = []
    if m.get("cols"):
        parts.append(f"{m.get('cols')}×{m.get('rows')}")
    if m.get("cases"):
        parts.append(f"{m['cases']} cases")
    parts.append(f"{m.get('rounds')} round{'s' if m.get('rounds', 1) != 1 else ''}")
    parts += [f"{m.get('duration_s', 0):.0f}s", m.get("when", "")]
    right = c(scn + " · ".join(parts), "dim")
    return [left + " " * max(1, W - vlen(left) - vlen(right) - 1) + right, c("━" * W, "cyan", dim=True)]


def scorecard(rep, W):
    mw = 18
    head = (f"{pad(c(rep.get('meta', {}).get('row_label', 'interaction'), 'dim'), 30)}{pad(c('n', 'dim'), 4, 'r')} {pad(c('typical', 'dim'), 10, 'r')} "
            f"{pad(c('worst', 'dim'), 10, 'r')}  {pad(c('vs budget (┃)', 'dim'), mw + 2)} "
            f"{pad(c('spread', 'dim'), 10)} {pad(c('frames', 'dim'), 6, 'r')} {pad(c('bytes', 'dim'), 8, 'r')}")
    lines = [head]
    for g in rep["latency"]:
        if g["id"] == "idle":
            continue
        col = RATING_COLOR[g["rating"]]
        m = g.get(g["metric"]) if isinstance(g.get(g["metric"]), dict) else g.get("settle")
        worst = m["max"] if m else None
        fr = g.get("frames")
        by = g.get("bytes")
        title = ("  ↳ " if g.get("parent") else "") + g["title"] + (c("  ✗ " + g["note"], "red") if g.get("note") else "")   # a sub group sits under its parent's overall figure
        lines.append(
            f"{c(GLYPH[g['rating']], col)} {pad(title, 28)}{pad(c(str(g['n']), 'dim'), 4, 'r')} "
            f"{pad(c(fmt_ms(g['value']), col, bold=True), 10, 'r')} {pad(c(fmt_ms(worst), 'dim'), 10, 'r')}  "
            f"{_meter(g['value'], g['budget_ms'], mw)}  {pad(spark(g['samples'], 10), 10)} "
            f"{pad(c(fmt_num(fr['med']) if fr else '', 'dim'), 6, 'r')} {pad(c(fmt_bytes(by['med']) if by else '', 'dim'), 8, 'r')}")
    return lines


def compare_block(rep, W):
    cmp_ = rep.get("compare")
    if not cmp_ or not cmp_["rows"]:
        return []
    lines = [c(f"against {cmp_.get('commit') or 'previous run'} ({cmp_.get('when') or ''})", "dim")]
    for which, n in (("this run", cmp_.get("new_noise")), ("the earlier run", cmp_.get("old_noise"))):
        if n is not None and n >= NOISY_CORES:
            lines.append(c(f"  {which} ran while ~{n:.1f} cores were busy with other work: its timings are inflated, so the changes below may be noise", "yellow"))
    for r in cmp_["rows"]:
        d = r["delta_pct"]
        big = abs(r["new"] - r["old"]) >= 2.0          # sub-2 ms moves are jitter, not change
        col = "green" if d <= -5 and big else "red" if d >= 15 and big else "dim"
        lines.append(f"{pad(r['title'], 34)}{pad(c(fmt_ms(r['old']), 'dim'), 11, 'r')} {c('→', 'faint')} {pad(c(fmt_ms(r['new']), 'white'), 10, 'r')}"
                     f"  {c(f'{d:+.0f}%', col, bold=True)}")
    return lines


def detail_table(g, W):
    """One group's cases: typical and worst time, output size and forks per call, with the case's own name (renderer, dataset,
    arguments). Rows are slowest first; a case without a figure is left out."""
    rows = [d for d in g.get("details", []) if d.get("settle") is not None]
    if not rows:
        return []
    nw = max(28, min(W - 52, max(vlen(d["detail"]) for d in rows) + 1))
    lines = [pad(c("case", "dim"), nw) + "".join(pad(c(h, "dim"), 10, "r") for h in ("typical", "worst", "bytes", "forks")) + "  " + c("vs budget (┃)", "dim")]
    for d in sorted(rows, key=lambda d: -d["settle"]):
        rating = "good" if d["settle"] <= g["budget_ms"] else "ok" if d["settle"] <= 2 * g["budget_ms"] else "slow"
        col = RATING_COLOR[rating]
        forks = d.get("forks")
        lines.append(pad(d["detail"], nw) + pad(c(fmt_ms(d["settle"]), col, bold=True), 10, "r") + pad(c(fmt_ms(d.get("p95") or d["settle"]), "dim"), 10, "r")
                     + pad(c(fmt_bytes(d["bytes"]) if d.get("bytes") is not None else "", "dim"), 10, "r")
                     + pad(c("" if forks is None else str(forks), "red" if forks else "dim"), 10, "r") + "  " + _meter(d["settle"], g["budget_ms"], 18))
    return lines


def hot_functions(rep, W, n=14):
    """The functions the time went into (rep["attr"]["functions"]): self and inclusive ms per case, calls and the self share as a bar."""
    fs = rep["attr"]["functions"][:n]
    if not fs:
        return []
    mx = fs[0]["self_ms"] or 1
    lines = [pad(c("function", "dim"), 34) + pad(c("self", "dim"), 10, "r") + pad(c("total", "dim"), 10, "r") + pad(c("calls", "dim"), 8, "r")
             + pad(c("per call", "dim"), 10, "r") + "  " + c("self share", "dim")]
    for f in fs:
        lines.append(pad(c(f["name"], "cyan"), 34) + pad(c(fmt_ms(f["self_ms"]), "white", bold=True), 10, "r") + pad(c(fmt_ms(f["incl_ms"]), "dim"), 10, "r")
                     + pad(c(fmt_num(f["calls"]) if f["calls"] else "–", "dim"), 8, "r")
                     + pad(c(fmt_ms(f["per_call_us"] / 1000) if f["per_call_us"] else "–", "dim"), 10, "r") + "  " + bar(f["self_ms"] / mx, 18, "cyan"))
    return lines


def hot_lines(rep, W, n=12):
    """The source lines the time went into (rep["attr"]["hot_lines"]), with a tag where most of it was a program or a fork."""
    lines = []
    for r in rep["attr"]["hot_lines"][:n]:
        tag = c(" ⟨program⟩", "red") if r["ex_ms"] > r["ms"] * 0.5 else c(" ⟨fork⟩", "red") if r["fk_ms"] > r["ms"] * 0.5 else ""
        lines.append(f"{pad(c(r['src'], 'cyan'), 26)} {pad(c(fmt_ms(r['ms']), 'white', bold=True), 9, 'r')} {pad(c('×' + fmt_num(r['hits']), 'dim'), 7, 'r')}  "
                     f"{c(r['code'], 'dim')}{tag}")
    return lines


def render(rep, W=None, details=True):
    """The whole default report as a list of lines: header, scorecard, one case table per group, diff against the previous run."""
    W = W or term.width()
    m = rep["meta"]
    out = header(rep, W)
    out.append("")
    out += panel("SCORECARD", scorecard(rep, W - 4), W, "cyan", m.get("legend") or "typical = median · budget = the line the bar is rated against")
    if details:
        for g in rep["latency"]:
            lines = detail_table(g, W - 4)
            if lines:
                out.append("")
                out += panel(g["title"], lines, W, "dim", f"{len(g['details'])} cases · budget {fmt_ms(g['budget_ms'])}")
    if details and rep.get("attr"):
        for title, lines in (("WHERE THE TIME GOES", hot_functions(rep, W - 4)), ("HOT SOURCE LINES", hot_lines(rep, W - 4))):
            if lines:
                out.append("")
                out += panel(title, lines, W, "purple", f"mean over {rep['attr'].get('cases_traced', '?')} traced cases")
    cb = compare_block(rep, W - 4)
    if cb:
        out.append("")
        out += panel("VS PREVIOUS RUN", cb, W, "teal")
    if m.get("method"):
        out += ["", c(m["method"], "faint")]
    return out
