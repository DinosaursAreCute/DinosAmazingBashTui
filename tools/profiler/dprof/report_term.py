"""Terminal report: overview first (verdict, scorecard, where time goes, findings), deep dive after."""
import textwrap

from . import term
from .term import c, pad, vlen, bar, spark, fmt_ms, fmt_bytes, fmt_num, panel, LAYER_COLOR, RATING_COLOR
from .analyze import LAYERS, LAYER_ORDER, layer_of
from .insights import short_path

SHORT = {"input": "Input", "loop": "Loop", "focus": "Focus", "scroll": "Scroll", "markup": "Markup", "cache": "Cache",
         "style": "Style", "layout": "Layout", "render": "Render", "flush": "Flush", "widgets": "Widget", "chrome": "Chrome",
         "term": "Term", "plugin": "Plugin", "config": "Config", "core": "Core", "app": "App", "diag": "Logging",
         "process": "Procs"}
GLYPH = {"good": "●", "ok": "●", "slow": "●", "na": "○"}
SEV = {"crit": ("CRIT", "red"), "warn": ("WARN", "yellow"), "info": ("INFO", "blue"), "good": ("GOOD", "green")}


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


# ── overview ─────────────────────────────────────────────────────────────────
def header(rep, W):
    m = rep["meta"]
    left = f" {c('◆', 'cyan', bold=True)} {c('DABT PROFILE', 'white', bold=True)}  " \
           f"{c(m.get('commit', ''), 'purple')} {c(m.get('branch', ''), 'dim')}" \
           f"{c(' · dirty' if m.get('dirty') else '', 'orange')}"
    scn = "" if m.get("scenario", "full") == "full" else f"scenario {m['scenario']} · "
    right = c(f"{scn}{m.get('cols')}×{m.get('rows')} · {m.get('rounds')} round{'s' if m.get('rounds', 1) != 1 else ''} · "
              f"{m.get('duration_s', 0):.0f}s · {m.get('when', '')}", "dim")
    return [left + " " * max(1, W - vlen(left) - vlen(right) - 1) + right, c("━" * W, "cyan", dim=True)]


def verdict(rep, W):
    lat = {g["id"]: g for g in rep["latency"]}
    tiles = []
    n = 5
    gap = 1
    w = (W - gap * (n - 1)) // n

    def tile_for(gid, title, pick="value"):
        g = lat.get(gid)
        if not g:
            return None
        v = g["value"]
        col = RATING_COLOR[g["rating"]]
        return _tile(title, fmt_ms(v), f"budget {fmt_ms(g['budget_ms'])}", col, min(1.0, v / (2 * g["budget_ms"])), w)

    t = [tile_for("startup.warm", "WARM START"), tile_for("nav.revisit", "PAGE SWITCH"),
         tile_for("hover.move", "HOVER FEEDBACK"), tile_for("focus.next", "FOCUS FEEDBACK")]
    idle = lat.get("idle", {}).get("idle")
    if idle:
        f = idle["frames_per_s"]
        col = "green" if f < 2 else "yellow" if f < 10 else "red"
        t.append(_tile("IDLE REPAINTS", f"{f:.0f} fr/s", f"{idle['bytes_per_s'] / 1024:.1f} KB/s · {idle['cpu_pct']:.1f}% cpu", col,
                       min(1.0, f / 20), w))
    else:
        t.append(None)
    t = [x for x in t if x]
    rows = max(len(x) for x in t) if t else 0
    return [(" " * gap).join(pad(x[i], w) for x in t) for i in range(rows)]


def scorecard(rep, W):
    mw = 18
    head = (f"{pad(c('interaction', 'dim'), 30)}{pad(c('n', 'dim'), 4, 'r')} {pad(c('typical', 'dim'), 10, 'r')} "
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
        title = g["title"] + (c("  ✗ " + g["note"], "red") if g.get("note") else "")
        lines.append(
            f"{c(GLYPH[g['rating']], col)} {pad(title, 28)}{pad(c(str(g['n']), 'dim'), 4, 'r')} "
            f"{pad(c(fmt_ms(g['value']), col, bold=True), 10, 'r')} {pad(c(fmt_ms(worst), 'dim'), 10, 'r')}  "
            f"{_meter(g['value'], g['budget_ms'], mw)}  {pad(spark(g['samples'], 10), 10)} "
            f"{pad(c(fmt_num(fr['med']) if fr else '', 'dim'), 6, 'r')} {pad(c(fmt_bytes(by['med']) if by else '', 'dim'), 8, 'r')}")
    return lines


def where_time_goes(rep, W):
    attr = rep["attr"]
    groups = []
    for gid, gv in attr["groups"].items():
        v = gv.get("w") if gid != "idle" else gv.get("a")
        if v and v["total_ms"] > 0:
            groups.append((gid, v))
    if not groups:
        return [c("no trace data (run without --no-trace)", "dim")]
    order = {g["id"]: i for i, g in enumerate(rep["latency"])}
    groups.sort(key=lambda gv: order.get(gv[0], 99))
    tot = {}
    for gid, v in groups:
        if gid.startswith("startup") or gid == "idle":
            continue
        for ly, ms in v["layers"].items():
            tot[ly] = tot.get(ly, 0.0) + ms
    cols = [ly for ly, _ in sorted(tot.items(), key=lambda kv: -kv[1])][:9]
    cw = 8
    title = {g["id"]: g["title"] for g in rep["latency"]}
    lines = []
    allsum = sum(tot.values()) or 1.0
    lines.append(f"{c('all interactions combined', 'dim')}")
    parts = [(tot.get(ly, 0.0), LAYER_COLOR.get(ly, "dim")) for ly in sorted(tot, key=lambda l: -tot[l])]
    lines.append(term.stacked(parts, W - 6))
    legend = "  ".join(f"{c('■', LAYER_COLOR.get(ly, 'dim'))} {LAYERS[ly][0]} {c(f'{tot[ly] / allsum * 100:.0f}%', 'dim')}"
                       for ly in sorted(tot, key=lambda l: -tot[l])[:9])
    lines.append(legend)
    lines.append("")
    lines.append(pad(c("ms per action", "dim"), 30) + "".join(pad(c(SHORT[ly], LAYER_COLOR.get(ly, "dim")), cw, "r") for ly in cols)
                 + pad(c("total", "dim"), cw + 1, "r"))
    for gid, v in groups:
        t = v["total_ms"]
        cells = []
        for ly in cols:
            ms = v["layers"].get(ly, 0.0)
            cells.append(_cell(f"{ms:.1f}" if ms >= 0.05 else "·", ms / t if t else 0, cw) if ms >= 0.05 else pad(c("·", "faint"), cw, "r"))
        name = title.get(gid, gid) if gid != "idle" else "Idle tick work (per 3 s)"
        lines.append(pad(name, 30) + "".join(cells) + " " + pad(c(fmt_ms(t), "white", bold=True), cw, "r"))
    lines.append(c(f"cell colour = share of that row · times calibrated to untraced speed (shell ×{attr['global_k']:.2f})", "faint"))
    return lines


def flows(rep, W):
    attr = rep["attr"]
    fl = attr["flow"][:10]
    lines = []
    if fl:
        mx = fl[0]["ms"]
        lines.append(c("who hands work to whom (time passed down the call stack, ms per pass of all interactions)", "dim"))
        for f in fl:
            a, b = f["from"], f["to"]
            lines.append(f"{pad(c(LAYERS[a][0], LAYER_COLOR.get(a, 'dim'), bold=True), 14, 'r')} {c('━▶', 'faint')} "
                         f"{pad(c(LAYERS[b][0], LAYER_COLOR.get(b, 'dim'), bold=True), 14)} {bar(f['ms'] / mx, 26, LAYER_COLOR.get(b, 'cyan'))} {c(fmt_ms(f['ms']), 'text')}")
    lines.append("")
    lines.append(c("hot path per scenario (heaviest call chain)", "dim"))
    for gid in ("nav.revisit", "nav.first", "hover.move", "focus.next", "click", "palette.open", "resize", "scroll.burst"):
        p = rep["paths"].get(gid)
        if not p:
            continue
        title = next((g["title"] for g in rep["latency"] if g["id"] == gid), gid)
        names = [n for n, _ in p]
        while names and names[0] in ("main", "source", "tui.start_cached", "tui.run"):
            names.pop(0)
            p = p[1:]
        chain = c(" › ", "faint").join(c(n, LAYER_COLOR.get(layer_of(n, attr["files"].get(n, "")), "text")) for n, _ in p[:5])
        lines.append(f"{pad(c(title, 'white'), 30)} {chain} {c(fmt_ms(p[0][1]) if p else '', 'dim')}")
    return lines


def findings(rep, W, limit=9):
    lines = []
    for ins in rep["insights"][:limit]:
        label, col = SEV[ins["sev"]]
        head = f"{_chip(label, col)} {c(ins['title'], 'white', bold=True)}"
        lines.append(head)
        body = textwrap.wrap(ins["detail"], W - 14) if ins["detail"] else []
        for b in body[:3]:
            lines.append("       " + c(b, "text"))
        if ins["where"]:
            lines.append("       " + c("↳ ", "faint") + c(ins["where"], "cyan", dim=True))
    if len(rep["insights"]) > limit:
        lines.append(c(f"       … {len(rep['insights']) - limit} more in the deep dive / report.html", "faint"))
    return lines


# ── deep dive ────────────────────────────────────────────────────────────────
def startup_gantt(rep, W):
    lines = []
    for which in ("warm", "cold"):
        s = rep["startup"].get(which)
        if not s:
            continue
        total = s["ready_ms"]
        bw = W - 6 - 42
        lines.append(f"{c(which.upper() + ' START', 'white', bold=True)}  {c('ready in', 'dim')} {c(fmt_ms(total), 'cyan', bold=True)}"
                     + (f"  {c('first pixel ' + fmt_ms(s['first_output_ms']), 'dim')}" if s.get("first_output_ms") else ""))
        for sp in s["spans"]:
            a = int(sp["start"] / total * bw)
            b = max(a + 1, int(sp["end"] / total * bw))
            row = " " * a + c("█" * (b - a), "cyan" if sp["end"] - sp["start"] < total * 0.4 else "orange")
            lines.append(f"  {pad(sp['label'], 24)} {pad(c(fmt_ms(sp['end'] - sp['start']), 'text'), 9, 'r')}  {row}")
        lines.append("")
    return lines[:-1] if lines else lines


def hot_functions(rep, W, n=16):
    fs = rep["attr"]["functions"][:n]
    if not fs:
        return []
    mx = fs[0]["self_ms"]
    lines = [pad(c("function", "dim"), 34) + pad(c("self", "dim"), 9, "r") + pad(c("total", "dim"), 10, "r") + pad(c("calls", "dim"), 8, "r")
             + pad(c("per call", "dim"), 10, "r") + "  " + pad(c("layer", "dim"), 14) + c("self share", "dim")]
    for f in fs:
        col = LAYER_COLOR.get(f["layer"], "text")
        lines.append(pad(c(f["name"], col), 34) + pad(c(fmt_ms(f["self_ms"]), "white", bold=True), 9, "r")
                     + pad(c(fmt_ms(f["incl_ms"]), "dim"), 10, "r") + pad(c(fmt_num(f["calls"]) if f["calls"] else "–", "dim"), 8, "r")
                     + pad(c(fmt_ms(f["per_call_us"] / 1000) if f["per_call_us"] else "–", "dim"), 10, "r") + "  "
                     + pad(c(LAYERS[f["layer"]][0], col), 14) + bar(f["self_ms"] / mx, 18, col))
    return lines


def hot_lines(rep, W, n=12):
    hl = rep["attr"]["hot_lines"][:n]
    lines = []
    for r in hl:
        tag = ""
        if r["ex_ms"] > r["ms"] * 0.5:
            tag = c(" ⟨program⟩", "red")
        elif r["fk_ms"] > r["ms"] * 0.5:
            tag = c(" ⟨fork⟩", "red")
        lines.append(f"{pad(c(r['src'], 'cyan'), 26)} {pad(c(fmt_ms(r['ms']), 'white', bold=True), 9, 'r')} {pad(c('×' + fmt_num(r['hits']), 'dim'), 7, 'r')}  "
                     f"{c(r['code'], 'dim')}{tag}")
    return lines


def call_graph(rep, W, n=14):
    es = rep["attr"]["edges"][:n]
    lines = []
    for e in es:
        la = layer_of(e["from"], rep["attr"]["files"].get(e["from"], ""))
        lb = layer_of(e["to"], rep["attr"]["files"].get(e["to"], ""))
        lines.append(f"{pad(c(e['from'], LAYER_COLOR.get(la, 'text')), 34)}{c('▶', 'faint')} {pad(c(e['to'], LAYER_COLOR.get(lb, 'text')), 34)}"
                     f"{pad(c(fmt_ms(e['ms']), 'white'), 9, 'r')}")
    return lines


def subprocs(rep, W):
    attr = rep["attr"]
    lines = []
    if attr["execs"]:
        lines.append(c("external programs  (per pass of every interaction)", "dim"))
        lines.append(pad(c("program", "dim"), 12) + pad(c("runs", "dim"), 7, "r") + pad(c("time", "dim"), 10, "r") + "  " + c("spawned by", "dim"))
        for e in attr["execs"][:8]:
            lines.append(pad(c(e["cmd"], "red", bold=True), 12) + pad(c(fmt_num(e["count"]), "text"), 7, "r")
                         + pad(c(fmt_ms(e["ms"]), "white"), 10, "r") + "  " + c(e["caller"], LAYER_COLOR.get(e["layer"], "text")))
    if attr["forks"]:
        lines.append("")
        lines.append(c("subshell fork sites", "dim"))
        lines.append(pad(c("site", "dim"), 50) + pad(c("forks", "dim"), 7, "r") + "  " + c("scenarios", "dim"))
        for f in attr["forks"][:8]:
            sc = ", ".join(sorted(f["groups"], key=lambda g: -f["groups"][g])[:3])
            lines.append(pad(c(f"{f['func']} ({f['src']})", LAYER_COLOR.get(f["layer"], "text")), 50)
                         + pad(c(fmt_num(f["count"]), "text"), 7, "r") + "  " + c(sc, "dim"))
    return lines


def slowest(rep, W, n=10):
    rows = []
    for g in rep["latency"]:
        for d in g.get("details", []):
            if d.get("settle") is not None and g["id"] not in ("idle", "shutdown"):
                rows.append((d["settle"], g, d))
    rows.sort(key=lambda r: -r[0])
    lines = [pad(c("action", "dim"), 40) + pad(c("done", "dim"), 10, "r") + pad(c("busy", "dim"), 10, "r") + pad(c("frames", "dim"), 8, "r") + pad(c("bytes", "dim"), 10, "r")]
    for s, g, d in rows[:n]:
        lines.append(pad(f"{g['id']} · {d['detail']}", 40) + pad(c(fmt_ms(s), RATING_COLOR[g["rating"]], bold=True), 10, "r")
                     + pad(c(fmt_ms(d["busy"]), "dim"), 10, "r") + pad(c(fmt_num(d["frames"]), "dim"), 8, "r")
                     + pad(c(fmt_bytes(d["bytes"]), "dim"), 10, "r"))
    return lines


def icicle(tree, files, W, depth=9):
    while len(tree["c"]) == 1 or (tree["c"] and tree["c"][0]["v"] > 0.97 * tree["v"]):   # shared prefix adds nothing
        tree = tree["c"][0]
    levels = [[] for _ in range(depth)]

    def walk(node, x0, x1, d):
        if d >= depth or x1 - x0 < 1:
            return
        levels[d].append((x0, x1, node["n"]))
        tot = node["v"] or 1.0
        x = x0
        for ch in node["c"]:
            wch = (x1 - x0) * ch["v"] / tot
            walk(ch, x, x + wch, d + 1)
            x += wch

    walk(tree, 0.0, float(W), 0)
    out = []
    for lv in levels:
        if not lv:
            break
        row, pos = [], 0
        for x0, x1, name in sorted(lv):
            a, b = int(round(x0)), int(round(x1))
            if b - a < 1 or a < pos:
                continue
            if a > pos:
                row.append(" " * (a - pos))
            ly = "process" if name.startswith("⟨") else ("loop" if name == "…small" else layer_of(name, files.get(name, "")))
            label = pad(name if b - a > 3 else "", b - a)
            r, g, bb = term.rgb(LAYER_COLOR.get(ly, "dim"))
            row.append(c(label[: b - a], (15, 17, 24), bg=(int(r * .85), int(g * .85), int(bb * .85))) if term.USE_COLOR else label)
            pos = b
        out.append("".join(row))
    return out


def calibration_block(rep, W):
    cal = rep.get("calibration")
    if not cal or not cal["rows"]:
        return []
    mae, bias = cal.get("mae_pct"), cal.get("bias_pct")
    col = "green" if mae is not None and mae <= 15 else "yellow" if mae is not None and mae <= 30 else "red"
    lines = [c("untraced probe time vs rescaled trace time, same function, same scenario (ms per action)", "dim"),
             (f"mean error {c(f'{mae:.0f}%', col, bold=True)}  bias {c(f'{bias:+.0f}%', col)}  over {cal['n']} functions ≥ 2 ms"
              if mae is not None else c("not enough data", "dim")),
             pad(c("scenario", "dim"), 18) + pad(c("function", "dim"), 34) + pad(c("real", "dim"), 10, "r")
             + pad(c("trace", "dim"), 10, "r") + pad(c("error", "dim"), 9, "r")]
    for x in cal["rows"][:14]:
        e = x["err_pct"]
        ec = "dim" if e is None else "green" if abs(e) <= 15 else "yellow" if abs(e) <= 30 else "red"
        lines.append(pad(x["group"], 18) + pad(c(x["func"], "text"), 34) + pad(c(fmt_ms(x["real_ms"]), "white"), 10, "r")
                     + pad(c(fmt_ms(x["est_ms"]), "dim"), 10, "r") + pad(c(f"{e:+.0f}%" if e is not None else "–", ec, bold=True), 9, "r"))
    return lines


def compare_block(rep, W):
    cmp_ = rep.get("compare")
    if not cmp_ or not cmp_["rows"]:
        return []
    lines = [c(f"against {cmp_.get('commit') or 'previous run'} ({cmp_.get('when') or ''})", "dim")]
    for r in cmp_["rows"]:
        d = r["delta_pct"]
        big = abs(r["new"] - r["old"]) >= 2.0          # sub-2 ms moves are jitter, not change
        col = "green" if d <= -5 and big else "red" if d >= 15 and big else "dim"
        lines.append(f"{pad(r['title'], 34)}{pad(c(fmt_ms(r['old']), 'dim'), 11, 'r')} {c('→', 'faint')} {pad(c(fmt_ms(r['new']), 'white'), 10, 'r')}"
                     f"  {c(f'{d:+.0f}%', col, bold=True)}")
    return lines


def render(rep, W=None, deep=True):
    W = W or term.width()
    out = []
    out += header(rep, W)
    out.append("")
    out += verdict(rep, W)
    out.append("")
    out += panel("HOW IT FEELS", scorecard(rep, W - 4), W, "cyan", "typical = median · budget = perceived-instant line")
    out.append("")
    out += panel("WHERE THE TIME GOES", where_time_goes(rep, W - 4), W, "purple")
    out.append("")
    out += panel("HOW WORK FLOWS", flows(rep, W - 4), W, "blue")
    out.append("")
    out += panel("FINDINGS", findings(rep, W - 4), W, "orange", f"{len(rep['insights'])} total")
    cb = compare_block(rep, W - 4)
    if cb:
        out.append("")
        out += panel("VS PREVIOUS RUN", cb, W, "teal")
    if not deep:
        return out
    out.append("")
    out.append(c("─" * 6 + " DEEP DIVE ", "dim") + c("─" * (W - 17), "line"))
    out.append("")
    tree = rep["trees"].get("*all interactions")
    sections = [
        ("Startup timeline", startup_gantt(rep, W - 4), "dim"),
        ("Flame · all interactions (top-down, from the first fork in the call chain)", icicle(tree, rep["attr"]["files"], W - 4) if tree else [], "dim"),
        ("Hot functions", hot_functions(rep, W - 4), "dim"),
        ("Hot source lines", hot_lines(rep, W - 4), "dim"),
        ("Call graph: heaviest edges", call_graph(rep, W - 4), "dim"),
        ("Subprocesses", subprocs(rep, W - 4), "dim"),
        ("Slowest individual actions", slowest(rep, W - 4), "dim"),
        ("Calibration check", calibration_block(rep, W - 4), "dim"),
    ]
    for title, lines, col in sections:
        if lines:
            out += panel(title, lines, W, col)
            out.append("")
    k = rep["attr"]["global_k"]
    out.append(c(f"method: real app in a pty, latency from in-app probes (untraced) · attribution from bash xtrace, "
                 f"in-shell time rescaled ×{k:.2f} to match untraced busy time (processes and forks are real).", "faint"))
    return out
