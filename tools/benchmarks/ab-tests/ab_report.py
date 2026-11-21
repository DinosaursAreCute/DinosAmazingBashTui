#!/usr/bin/env python3
"""Reporter for ab.sh runs: turns a run dir (meta.txt + samples.tsv) into the shared results shape of tools/benchmarks/reporting
and prints it with the shared reporter (header, scorecard of sides rated against the base side, diff against an earlier run),
plus a RESULT panel in plain words. Writes the colourless text to DIR/report.txt with --save. Python standard library only.

  ab_report.py RUN_DIR [--vs RUN_DIR|none] [--save] [--no-color]
  ab_report.py --suite RUN_DIR... [--save FILE]   one table over several runs (what a suite prints at the end)
  ab_report.py RUN_DIR --live --pid PID   follow a run that ab.sh is writing (warmup.tsv, samples.tsv) with the shared live view
    --vs  the earlier run for the diff block; default: the latest earlier run of the same scenario name in the same runs dir
"""
import argparse
import math
import os
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))   # tools/benchmarks: the shared reporting package

from reporting import default_reporter as dr, term                          # noqa: E402
from reporting.live import LiveUI                                            # noqa: E402
from reporting.stats import compare_groups, group, med, stats                # noqa: E402
from reporting.term import c, pad, panel, fmt_ms, vlen                       # noqa: E402


def load(run_dir):
    """meta dict, [(side, x)] in order, {side: [us]} from a run dir."""
    meta, sides = {}, []
    with open(os.path.join(run_dir, "meta.txt"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("--- "):
                break
            k, _, rest = line.rstrip("\n").partition("\t")
            if k == "side":
                parts = rest.split("\t")
                sides.append((parts[0], parts[2] if len(parts) > 2 and parts[2] != "" else None))
                meta.setdefault("_per", {})[parts[0]] = float(parts[3]) if len(parts) > 3 and parts[3] != "" else 0.0
            else:
                meta[k] = rest
    samples = {s: [] for s, _ in sides}
    with open(os.path.join(run_dir, "samples.tsv"), encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) == 3 and p[1] in samples:
                samples[p[1]].append(int(p[2]))
    return meta, sides, samples


def fmt_each(us):
    """Time of ONE unit or call, given in microseconds: ns / µs / ms."""
    if us is None:
        return "–"
    a = abs(us)
    return f"{us * 1000:.0f} ns" if a < 1 else f"{us:.2f} µs" if a < 1000 else f"{us / 1000:.2f} ms"


def per_costs(meta, st, side, base, control):
    """(per unit, net per unit, net per inner op) in us for one side; None where not defined. net = median minus the control's."""
    units = int(meta.get("units") or 0)
    if not units:
        return None, None, None
    gross = st[side]["med"] * 1000 / units
    net = (st[side]["med"] - st[control]["med"]) * 1000 / units if control in st else None
    n = meta.get("_per", {}).get(side) or 0
    return gross, net, (net / n if net is not None and n else None)


def build(run_dir):
    meta, sides, samples = load(run_dir)
    control = meta.get("control") or ""
    base = control if control in samples else sides[0][0]
    base_ms = med([v / 1000 for v in samples[base]])
    groups = [group(s, s, [v / 1000 for v in samples[s]], base_ms) for s, _ in sides]   # budget = base median: bar tick = "as fast as base"
    git = meta.get("git", "")
    try:
        when = datetime.strptime(meta.get("stamp", ""), "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%d %H:%M")
    except ValueError:
        when = meta.get("stamp", "")
    dur = 0.0
    try:
        with open(os.path.join(run_dir, "duration_s"), encoding="utf-8") as f:
            dur = float(f.read())
    except (OSError, ValueError):
        pass
    rep = {"meta": {"title": "A/B  " + meta.get("name", ""), "commit": git.replace("+dirty", ""), "branch": meta.get("desc", ""),
                    "dirty": git.endswith("+dirty"), "rounds": int(meta.get("rounds", 1)), "duration_s": dur, "when": when,
                    "row_label": "side", "legend": f"typical = median per sample · ┃ = base side ({base}) median · bar runs to 2x",
                    "method": "sides run interleaved, starting side rotates each round · verdict: Welch t on the means, |t|<2 = within noise"},
           "latency": groups, "compare": None}
    return rep, meta, sides, samples, base


def welch_t(a, b):
    na, nb = len(a), len(b)
    if na < 2 or nb < 2:
        return 0.0
    ma, mb = sum(a) / na, sum(b) / nb
    va = sum((x - ma) ** 2 for x in a) / (na - 1)
    vb = sum((x - mb) ** 2 for x in b) / (nb - 1)
    se = math.sqrt(va / na + vb / nb)
    return abs(mb - ma) / se if se else 0.0


def result_panel(rep, meta, sides, samples, base, W):
    """Slowest/fastest per side, then one plain sentence per side against the base (median based), per-unit and slope lines."""
    units = int(meta.get("units") or 0)
    control = meta.get("control") or ""
    ms = {s: [v / 1000 for v in samples[s]] for s, _ in sides}
    st = {s: stats(ms[s]) for s in ms}
    un, pn = meta.get("unit_name", "unit"), meta.get("per_name", "call")
    lines = []
    for s, _ in sides:
        x = st[s]
        lines.append(f"{pad(s, 24)} median {pad(c(fmt_ms(x['med']), 'white', bold=True), 11)}  slowest {pad(c(fmt_ms(x['max']), 'red'), 11)}  "
                     f"fastest {pad(c(fmt_ms(x['min']), 'green'), 11)}" + (c("  (base)", "dim") if s == base else ""))
        gross, net, opc = per_costs(meta, st, s, base, control)
        if gross is not None:
            bits = [f"{c(fmt_each(gross), 'white')} per {un}"]
            if net is not None and s != control:
                bits.append(f"net {c(fmt_each(net), 'white')} per {un}")
            if opc is not None:
                bits.append(c(f"= {fmt_each(opc)} per {pn}", "cyan", bold=True))
            lines.append(c(f"{'':24} ", "dim") + c("  ·  ", "faint").join(bits))
    lines.append("")
    verdicts, last = [], ""
    for s, _ in sides:
        if s == base:
            continue
        d = st[s]["med"] - st[base]["med"]
        pct = abs(d) / st[base]["med"] * 100 if st[base]["med"] else 0.0
        t = welch_t(ms[base], ms[s])
        per = ""
        if units:
            _, net, opc = per_costs(meta, st, s, base, control)
            per = f" = {'+' if d > 0 else '-'}{fmt_each(abs(d) * 1000 / units)} per {un}"
            if opc is not None and base == control:
                per += f", {fmt_each(opc)} per {pn}"
        if t < 2:
            lines.append(f"{c(s, 'white', bold=True)} vs {base}: {c('NO CLEAR DIFFERENCE', 'yellow', bold=True)} - "
                         f"{'faster' if d < 0 else 'slower'} by {pct:.1f}% / {fmt_ms(abs(d))}{per} on average is within noise (t={t:.1f})")
            last = f"{s} vs {base}: {'-' if d < 0 else '+'}{pct:.1f}% ~noise (t={t:.1f})"
        else:
            word, col = ("FASTER", "green") if d < 0 else ("SLOWER", "red")
            lines.append(f"{c(s, 'white', bold=True)} is {c(word, col, bold=True)} than {base} by an average of "
                         f"{c(f'{pct:.1f}%', col, bold=True)} / {c(fmt_ms(abs(d)), col, bold=True)}{per}")
            last = f"{s} vs {base}: {'-' if d < 0 else '+'}{pct:.1f}% {word.lower()} (t={t:.1f})"
    xs = [(float(x), s) for s, x in sides if x is not None]
    summary = last
    if len(xs) == len(sides) >= 3:
        ys = []
        for x, s in xs:
            v = st[s]["med"] - (st[control]["med"] if control in st else 0)
            ys.append(v * 1e6 / units if units else v * 1000)
        n = len(xs)
        sx, sy = sum(x for x, _ in xs), sum(ys)
        sxx, sxy = sum(x * x for x, _ in xs), sum(x * y for (x, _), y in zip(xs, ys))
        den = n * sxx - sx * sx
        if den:
            sl = (n * sxy - sx * sy) / den
            ic = (sy - sl * sx) / n
            u = "ns/unit" if units else "us"
            lines.append("")
            lines.append(f"cost per x: {c(f'{sl:.1f} {u}', 'cyan', bold=True)}   intercept {ic:.1f} {u}")
            summary = f"slope={sl:.1f} {u} per x, intercept={ic:.1f} {u}"
    sub = f"\"average\" = median over {rep['meta']['rounds']} rounds" + (f" · one sample = {units:,} {un}s" if units else "")
    return panel("RESULT", lines, W, "green", sub), summary


def previous_run(run_dir, name):
    """Latest earlier run dir with the same scenario name next to RUN_DIR, or None."""
    parent = os.path.dirname(os.path.abspath(run_dir))
    me = os.path.basename(os.path.abspath(run_dir))
    best = None
    for d in sorted(os.listdir(parent)):
        p = os.path.join(parent, d)
        if d < me and os.path.isfile(os.path.join(p, "meta.txt")):
            try:
                m = load(p)[0]
            except OSError:
                continue
            if m.get("name") == name:
                best = p
    return best


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


class Tail:
    """Complete new lines of a file that another process appends to."""

    def __init__(self, path):
        self.path, self.pos, self.buf = path, 0, ""

    def lines(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                f.seek(self.pos)
                chunk = f.read()
                self.pos = f.tell()
        except OSError:
            return []
        self.buf += chunk
        *done, self.buf = self.buf.split("\n")
        return [ln for ln in done if ln]


def live(run_dir, pid):
    """The shared LiveUI over a running ab.sh: every finished sample is one line (time, its side, how it compares with the base
    side so far); the footer names the sample that is running now (it knows the rotation) with phase, progress and ETA."""
    meta, sides, _ = load(run_dir)
    names = [s for s, _ in sides]
    ns, rounds, warm = len(names), int(meta["rounds"]), int(meta["warmup"])
    control = meta.get("control") or ""
    base = control if control in names else names[0]
    units_n, unit_name = int(meta.get("units") or 0), meta.get("unit_name", "unit")
    seen = {s: [] for s in names}

    def info_of(side):
        m = med([v / 1000 for v in seen[base]]) if seen[base] else None
        return (side, "render", m)   # rated against the base side's median so far: green = as fast as base, red = over 2x

    phases = ([("warm", "Warmup", 1, warm * ns)] if warm else []) + [("run", "Measuring", 1, rounds * ns)]
    ui = LiveUI(phases, info_of=info_of, hint="ctrl+c aborts the run · colours: green = as fast as the base side so far, red = over 2x", show_trace=False)
    ui.begin([f" {c('◆', 'cyan', bold=True)} {c('A/B  ' + meta.get('name', ''), 'white', bold=True)}  "
              f"{c(f'{ns} sides · {rounds} rounds · {warm} warmup · base {base}', 'dim')}",
              f" {c(meta.get('desc', ''), 'dim')}", ""])
    total = {"warm": warm * ns, "run": rounds * ns}
    files = {"warm": Tail(os.path.join(run_dir, "warmup.tsv")), "run": Tail(os.path.join(run_dir, "samples.tsv"))}
    for key, _, _, n in phases:
        ui.phase(key, "", n)
        count = 0
        ui.step_begin(names[0] if key == "warm" else names[1 % ns])
        while count < total[key]:
            got = files[key].lines()
            for line in got:
                p = line.split("\t")
                if len(p) != 3 or p[1] not in seen:
                    continue
                side, ms = p[1], int(p[2]) / 1000
                if key == "run":
                    seen[side].append(int(p[2]))
                extra = []
                if key == "run" and side != base and seen[base]:
                    d = (med(seen[side]) - med(seen[base])) / med(seen[base]) * 100
                    extra.append(f"{d:+.0f}% vs {base} (median so far)")
                if units_n:
                    extra.append(f"= {fmt_each(int(p[2]) / units_n)} per {unit_name}")
                count += 1
                desc = f"{side}  {'warmup' if key == 'warm' else 'round'} {p[0]}/{warm if key == 'warm' else rounds}"
                ui.cur_t0 = time.time() - ms / 1000   # "took" = the sample itself, not how late this poll saw it
                ui.step_end(desc, {"group": side, "ok": True, "settle_ms": ms, "extra": extra})
                if count < total[key]:
                    nxt = names[count % ns] if key == "warm" else names[((count // ns + 1) + count % ns) % ns]
                    ui.step_begin(nxt)
            if not got:
                if not alive(pid):
                    ui.warn("run ended early")
                    ui.finish()
                    return
                time.sleep(0.1)
    ui.finish()


def suite_table(run_dirs, W):
    """One row per side of every run: median, against the run's base side, verdict, per-unit cost. Plain words, same rules as RESULT."""
    head = (f"{pad(c('scenario', 'dim'), 18)}{pad(c('side', 'dim'), 18)}{pad(c('median', 'dim'), 11, 'r')}{pad(c('slowest', 'dim'), 11, 'r')}"
            f"{pad(c('fastest', 'dim'), 11, 'r')}{pad(c('per unit', 'dim'), 11, 'r')}{pad(c('per call*', 'dim'), 11, 'r')}  {c('vs base', 'dim')}")
    lines, wins = [head], []
    for d in run_dirs:
        meta, sides, samples = load(d)
        names = [s for s, _ in sides]
        control = meta.get("control") or ""
        base = control if control in names else names[0]
        units = int(meta.get("units") or 0)
        ms = {s: [v / 1000 for v in samples[s]] for s in names}
        st = {s: stats(ms[s]) for s in names}
        lines.append(c("─" * min(W - 6, 100), "line"))
        for i, s in enumerate(names):
            x = st[s]
            if x is None:
                continue
            gross, net, opc = per_costs(meta, st, s, base, control)
            per = fmt_each(gross) if gross is not None else ""
            pc = fmt_each(opc) if opc is not None else ""
            if s == base:
                vs = c("(base)", "dim")
            else:
                dlt = x["med"] - st[base]["med"]
                pct = abs(dlt) / st[base]["med"] * 100 if st[base]["med"] else 0.0
                t = welch_t(ms[base], ms[s])
                vs = (c(f"~noise ({'-' if dlt < 0 else '+'}{pct:.1f}%, t={t:.1f})", "yellow") if t < 2 else
                      c(f"{pct:.0f}% {'FASTER' if dlt < 0 else 'SLOWER'}", "green" if dlt < 0 else "red", bold=True))
            lines.append(f"{pad(c(meta.get('name', '') if i == 0 else '', 'cyan', bold=True), 18)}{pad(s, 18)}{pad(c(fmt_ms(x['med']), 'white', bold=True), 11, 'r')}"
                         f"{pad(c(fmt_ms(x['max']), 'dim'), 11, 'r')}{pad(c(fmt_ms(x['min']), 'dim'), 11, 'r')}{pad(c(per, 'dim'), 11, 'r')}{pad(c(pc, 'cyan', bold=True), 11, 'r')}  {vs}")
    return panel("SUITE SUMMARY", lines, W, "purple", f"{len(run_dirs)} runs · median per sample · per unit = one loop iteration · *per call = net of the control, one call/op")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dir", nargs="*")
    ap.add_argument("--suite", action="store_true")
    ap.add_argument("--vs", default=None)
    ap.add_argument("--save", nargs="?", const="", default=None)
    ap.add_argument("--no-color", action="store_true")
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--pid", type=int, default=0)
    a = ap.parse_args()
    term.init(False if a.no_color else None)
    if a.suite:
        W = min(term.width(), 140)
        print("\n".join(suite_table(a.run_dir, W)))
        if a.save:
            term.set_color(False)
            with open(a.save, "w", encoding="utf-8") as f:
                f.write("\n".join(suite_table(a.run_dir, W)) + "\n\n" + "\n".join(a.run_dir) + "\n")
        return
    a.run_dir = a.run_dir[0]
    if a.live:
        return live(a.run_dir, a.pid)
    rep, meta, sides, samples, base = build(a.run_dir)
    vs = a.vs if a.vs else previous_run(a.run_dir, meta.get("name"))
    if vs and vs != "none":
        er, *_ = build(vs)
        rep["compare"] = compare_groups(rep["latency"], er)
    W = min(term.width(), 140)

    def render():
        res, summary = result_panel(rep, meta, sides, samples, base, W)
        out = dr.header(rep, W) + [""] + res + [""]
        out += panel("SCORECARD", dr.scorecard(rep, W - 4), W, "cyan", rep["meta"]["legend"])
        cb = dr.compare_block(rep, W - 4)
        if cb:
            out += [""] + panel("VS PREVIOUS RUN", cb, W, "teal")
        out += ["", c(rep["meta"]["method"], "faint"), "summary: " + summary]
        return out

    print("\n".join(render()))
    if a.save is not None:
        term.set_color(False)
        with open(os.path.join(a.run_dir, "report.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(render()) + "\n")


if __name__ == "__main__":
    main()
