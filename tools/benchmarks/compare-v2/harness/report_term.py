"""Terminal report (rich). Same function renders live to the console and, with plain=True, to report.txt."""
from rich import box
from rich.console import Console, Group
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from .stats import METRICS, PRIMARY

BLOCKS = " ▏▎▍▌▋▊▉█"


def bar(value, vmax, width, color):
    if not vmax or value is None:
        return Text("")
    eighths = max(1, round(value / vmax * width * 8))
    full, part = divmod(eighths, 8)
    return Text("█" * full + (BLOCKS[part] if part else ""), style=color)


def num(v, key, signed=False):
    if v is None:
        return "-"
    dec = METRICS[key][2]
    if key.endswith("_kb"):
        return f"{v / 1024:.1f} MB"
    if key == "bytes" and v >= 10240:
        return f"{v / 1024:.1f} kB"
    if key == "bytes_s" and v >= 10240:
        return f"{v / 1024:.1f} kB/s"
    return f"{v:+.{dec}f}" if signed else f"{v:.{dec}f}"


def verdict_text(c, base, other, key):
    """Plain-language comparison of `other` against `base` for one metric."""
    if not c:
        return Text("-", style="dim")
    if c["verdict"] == "tie":
        return Text("≈ same", style="dim")
    if c["verdict"] == "unclear":
        r = c["ratio"]
        return Text(f"unclear ({r:.2f}×, CI spans 1)" if r else "unclear", style="yellow")
    winner, loser = (base, other) if c["verdict"] == "a" else (other, base)
    ci = c["ci"]
    f = c["ratio"] if c["verdict"] == "a" else 1 / c["ratio"]
    lo, hi = (ci if c["verdict"] == "a" else (1 / ci[1], 1 / ci[0]))
    t = Text()
    t.append(f"{winner['label']} {f:.2f}× ", style=f"bold {winner['color']}")
    t.append("faster" if METRICS[key][1] == "ms" else "lower")
    t.append(f"  [{lo:.2f}–{hi:.2f}]", style="dim")
    return t


def cell_value(a, key):
    s = a["metrics"][key]["sum"]
    if not s:
        return Text("-", style="dim")
    t = Text(num(s["median"], key))
    if s["n"] > 2:
        lo, hi = s["ci"]
        t.append(f" [{num(lo, key)}–{num(hi, key)}]", style="dim")
    if s["n"] > 2 and s["cv"] > 0.25:
        t.append(" ~", style="yellow")
    if s["outliers"]:
        t.append(" °", style="yellow")
    return t


def latency_table(an, meta, steps, title, compact=False):
    apps = {a["name"]: a for a in meta["apps"]}
    base = apps[an["base"]]
    t = Table(title=title, title_justify="left", box=box.SIMPLE_HEAD, header_style="bold", pad_edge=False, show_edge=False)
    cols = [("step", "left", 17), ("app", "left", 8), ("done  median [95% CI]", "right", 22), ("", "left", 14), ("ready", "right", 7),
            ("CPU", "right", 5), ("written", "right", 8), ("paints", "right", 6), (f"vs {base['label']}", "left", 20)]
    for col, j, w in cols:
        t.add_column(col, justify=j, no_wrap=True, min_width=w)
    for st in steps:
        vmax = max((st["apps"][n]["metrics"]["settled_ms"]["sum"] or {"median": 0})["median"] for n in an["apps"])
        for i, n in enumerate(an["apps"]):
            a, app = st["apps"][n], apps[n]
            m = a["metrics"]
            flags = Text()
            if a["ok"][1] and a["ok"][0] < a["ok"][1]:
                flags.append(f" {a['ok'][0]}/{a['ok'][1]} ok", style="bold red")
            if a["stale"]:
                flags.append(" stale!", style="yellow")
            med = lambda k: (m[k]["sum"] or {}).get("median")
            ready = cell_value(a, "settled_ms")
            ready.append_text(flags)
            t.add_row(Text(st["name"], style="bold") if i == 0 else "", Text(app["label"], style=app["color"]), ready,
                      bar(med("settled_ms"), vmax, 14, app["color"]), num(med("ready_ms"), "ready_ms"), num(med("cpu_ms"), "cpu_ms"),
                      num(med("bytes"), "bytes"), num(med("paints"), "paints"),
                      verdict_text(st["cmp"].get(n, {}).get("settled_ms"), base, app, "settled_ms") if i else Text("baseline", style="dim"),
                      end_section=i == len(an["apps"]) - 1)
    return t


def simple_table(an, meta, steps, title, keys):
    apps = {a["name"]: a for a in meta["apps"]}
    base = apps[an["base"]]
    t = Table(title=title, title_justify="left", box=box.SIMPLE_HEAD, header_style="bold", pad_edge=False, show_edge=False)
    t.add_column("step", no_wrap=True)
    t.add_column("app", no_wrap=True)
    for k in keys:
        t.add_column(METRICS[k][0], justify="right", no_wrap=True)
    t.add_column(f"vs {base['label']} ({METRICS[PRIMARY[steps[0]['kind']]][0]})", no_wrap=True)
    for st in steps:
        for i, n in enumerate(an["apps"]):
            a, app = st["apps"][n], apps[n]
            t.add_row(Text(st["name"], style="bold") if i == 0 else "", Text(app["label"], style=app["color"]),
                      *[cell_value(a, k) for k in keys],
                      verdict_text(st["cmp"].get(n, {}).get(PRIMARY[st["kind"]]), base, app, PRIMARY[st["kind"]]) if i else Text("baseline", style="dim"),
                      end_section=i == len(an["apps"]) - 1)
    return t


def summary_panel(an, meta):
    apps = {a["name"]: a for a in meta["apps"]}
    base = apps[an["base"]]
    lines = []
    for n, s in an["score"].items():
        o = apps[n]
        if s["geomean"]:
            g = s["geomean"]
            fast, slow, f = (base, o, g) if g > 1 else (o, base, 1 / g)
            t = Text()
            t.append(f"{fast['label']}", style=f"bold {fast['color']}")
            t.append(f" is {f:.2f}× faster than ")
            t.append(f"{slow['label']}", style=f"bold {slow['color']}")
            t.append(f" on interaction latency, measured to the last visible change (geometric mean over {s['n']} steps).  ")
            t.append(f"{base['label']} better in {s['base_better']}, {o['label']} better in {s['other_better']}, no clear difference in {s['tie']}.", style="dim")
            lines.append(t)
        st = next((r for r in an["steps"] if r["name"] == "startup.warm"), None)
        if st:
            lines.append(Text.assemble(("warm startup:  ", "dim"), verdict_text(st["cmp"].get(n, {}).get("settled_ms"), base, o, "settled_ms")))
    return Panel(Group(*lines), title="summary", title_align="left", border_style="green")


def header(meta):
    e = meta["env"]
    g = Table.grid(padding=(0, 2))
    g.add_row(Text("scenario", style="dim"), Text(f"{meta['scenario']} — {meta['title']}"))
    for a in meta["apps"]:
        g.add_row(Text("app", style="dim"), Text.assemble((a["label"], f"bold {a['color']}"), (f"  {a['version']}", "dim"),
                                                          (f"   keys: {a['keyboard']}" if a.get("keyboard") else "", "dim")))
    g.add_row(Text("run", style="dim"), Text(f"{meta['rounds']} rounds (+{meta['warmup']} warm-up) · {meta['cols']}x{meta['rows']} · {meta['duration_s']}s · {meta['started']}"))
    g.add_row(Text("machine", style="dim"), Text(f"{e['cpu']} · {e['logical_cpus']} CPUs · kernel {e['kernel']} · governor {e['governor']} · load {' '.join(e['loadavg'])}"))
    g.add_row(Text("isolation", style="dim"), Text(f"app on CPUs {e['pinned_app'] or 'any'} · harness on {e['pinned_harness'] or 'any'} · python {e['python']} · bash {e['bash']} · repo {e['git']}"))
    return Panel(g, title="compare-v2", title_align="left", border_style="blue")


NOTES = """\
how to read:  done = ms from the input to the LAST visible change of the screen; it is the number compared. ready = when the expected text first showed.
              paints = visible screen changes; CPU = app process tree incl. reaped children; written = bytes the app sent to the terminal.
statistics:   one value per round (median of that round's samples); [lo–hi] = bootstrap 95% CI of the median across rounds; "vs" ratios
              are medians of other/base with a bootstrap CI. "≈ same" = gap below the noise floor or < 5%; "unclear" = CI spans 1.
flags:        ~ noisy (CV > 25%)   ° outlier rounds present (kept, never dropped)   k/n ok = rounds where the expected text appeared   stale! = expectation was already true before the input
method:       fresh process + HOME per round, warm-up rounds discarded, apps interleaved in shuffled order, pinned CPUs, output stamped when read and
              replayed offline into a terminal emulator (synchronized updates honoured), terminal answers capability queries like a modern terminal.
keys:         input arrives at human speed. Modified keys (alt+x, ctrl+x) are sent as a terminal would send them to that app: kitty CSI-u when the app
              asked for the kitty keyboard protocol, the legacy ESC prefix otherwise (see the keys line in the header for what each app got)."""


def skew_panel(meta):
    """Loud banner for a run whose timings cannot be taken at face value. Printed at the top and the bottom of every report."""
    reasons = meta.get("skew") or []
    if not reasons:
        return None
    body = Group(Text("SKEWED RUN: do not quote these timings as real.", style="bold"), *[Text("• " + r) for r in reasons])
    return Panel(body, border_style="red", style="red", title="⚠ skewed", title_align="left")


def render(res, an, file=None, plain=False):
    con = Console(file=file, width=150 if plain else max(Console().width, 150), force_terminal=None if not plain else False, color_system=None if plain else "auto")
    meta = res["meta"]
    sk = skew_panel(meta)
    if sk:
        con.print(sk)
    con.print(header(meta))
    for w in meta.get("warnings", []):
        con.print(Text("⚠ " + w, style="yellow"))
    for e in meta.get("errors", []):
        con.print(Text(f"✗ {e['app']} round {e['round']}: {e['error'].strip().splitlines()[-1]}", style="red"))
    con.print(summary_panel(an, meta))
    steps = an["steps"]
    lat = [s for s in steps if s["kind"] == "latency"]
    con.print(latency_table(an, meta, [s for s in lat if s["name"].startswith("startup")], "startup  (spawn → first correct frame)"))
    con.print(latency_table(an, meta, [s for s in lat if not s["name"].startswith("startup")], "interaction  (input → expected screen)"))
    for kind, title, keys in (("idle", "idle  (app sits still)", ["cpu_pct", "wakeups_s", "bytes_s"]), ("memory", "memory", ["pss_kb", "rss_kb", "procs", "threads"])):
        part = [s for s in steps if s["kind"] == kind]
        if part:
            con.print(simple_table(an, meta, part, title, keys))
    con.print(Text(NOTES, style="dim"))
    if sk:
        con.print(sk)
