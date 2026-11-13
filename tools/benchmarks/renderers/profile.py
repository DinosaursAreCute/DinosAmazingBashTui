#!/usr/bin/env python3
"""Renderer profiler: times every renderer of lib/terminal_renderer.sh on several datasets and argument sets (harness.sh does the measuring
in bash), and reports with the shared reporter, live view and viewer window of tools/benchmarks/reporting. It takes the same options as the
DABT profiler (tools/benchmarks/profiler/profile.sh), applied to renderers: scenario selectors, rounds, jobs, a trace for where the time
goes inside a renderer, a diff against the previous run, saved reports and a second window.

  profile.sh                              ask which scenario (a terminal), else everything
  profile.sh --scenario charts,small      scenarios by name or number (--list-scenarios)
  profile.sh --quick | --deep             8 calls per case | 5 rounds
  profile.sh --trace                      also show where the time goes inside the renderers (slow)
  profile.sh --report DIR                 re-render a saved run
"""
import argparse
import collections
import concurrent.futures
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))   # tools/benchmarks: the shared reporting package

from reporting import default_reporter, term                  # noqa: E402
from reporting.live import LiveUI                              # noqa: E402
from reporting.stats import compare_groups, group, med, pct   # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
REPORTS = os.path.join(HERE, "reports")
SCENARIO_DIR = os.path.join(HERE, "scenarios")
WATCH_ROWS, WATCH_COLS = 50, 110   # the --watch window: what the renderers draw, not the report
DEFAULT_BUDGET_MS = 5.0
BUILTINS = set("alias bg bind break builtin caller cd command compgen complete continue declare dirs echo enable eval exec exit export false "
               "getopts hash help history jobs kill let local mapfile popd printf pushd pwd read readarray readonly return set shift shopt "
               "source test times trap true type typeset ulimit umask unalias unset wait [ [[ (( . : ! { } if then else elif fi for while "
               "until do done case esac in function select time".split())


class Scenarios:
    """The scenario file a run is based on (scenarios/renderers.py by default): its cases file, option defaults and scenario list."""

    def __init__(self, spec):
        path = spec if os.path.isfile(spec) else os.path.join(SCENARIO_DIR, spec if spec.endswith(".py") else spec + ".py")
        if not os.path.isfile(path):
            raise SystemExit(f"no scenario file '{spec}' (a path, or a name in {os.path.relpath(SCENARIO_DIR, REPO)}/)")
        mod_spec = importlib.util.spec_from_file_location("renderer_scenarios", path)
        self.mod = importlib.util.module_from_spec(mod_spec)
        mod_spec.loader.exec_module(self.mod)
        self.cases_file = os.path.join(os.path.dirname(os.path.abspath(path)), self.mod.CASES)
        self.options = dict(self.mod.OPTIONS)
        self.scenarios = list(self.mod.SCENARIOS)
        self.title = self.mod.TITLE

    def set_options(self, items):
        for item in items:
            name, _, value = item.partition("=")
            if name not in self.options or not value:
                raise SystemExit(f"--set {item}: expected NAME=VALUE with NAME one of {', '.join(self.options)}")
            self.options[name] = value

    def resolve(self, spec, rows):
        """'2,charts' / 'text small' -> ids of the cases they select, in case order. rows: [(id, renderer, tags)]. Raises ValueError."""
        names = [n for n, _, _ in self.scenarios]
        picked = []
        for tok in spec.replace(",", " ").split():
            if tok.isdigit() and 1 <= int(tok) <= len(names):
                picked.append(names[int(tok) - 1])
            elif tok in names:
                picked.append(tok)
            else:
                raise ValueError(f"unknown scenario '{tok}' (try: {', '.join(names)} or 1-{len(names)})")
        picked = picked or [names[0]]
        wanted = set()
        by_name = {n: s for n, _, s in self.scenarios}
        for name in picked:
            s = by_name[name]
            for cid, renderer, tags in rows:
                if s is None or (renderer in s["only"] if "only" in s else True) and (any(t in tags.split(",") for t in s["tags"]) if "tags" in s else True):
                    wanted.add(cid)
        return picked, [cid for cid, _, _ in rows if cid in wanted]


def git(*args):
    try:
        return subprocess.check_output(["git", *args], cwd=REPO, stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


class Harness:
    """harness.sh in a clean environment: a private HOME, a fixed locale and width, no terminal."""

    def __init__(self, scn, width):
        self.scn = scn
        self.env = None
        self.width = width

    def environment(self, show_fd=None):
        home = tempfile.mkdtemp(prefix="dabt-renderers-home-")
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "XDG_CONFIG_HOME": home + "/.config", "XDG_DATA_HOME": home + "/.local/share",
               "XDG_CACHE_HOME": home + "/.cache", "XDG_STATE_HOME": home + "/.local/state", "LC_ALL": "C.UTF-8", "TZ": "UTC", "TR_WIDTH": str(self.width),
               "TERM": "dumb", "NO_COLOR": "1", "RC_SHOW_WAIT": self.scn.options.get("wait", "0")}
        if show_fd is not None:
            env["RC_SHOW_FD"] = str(show_fd)
        return env, home

    def run(self, extra, on_row=None, show_fd=None):
        """Returns (status, stdout). ON_ROW(line) is called for every line while the harness is still running."""
        env, home = self.environment(show_fd)
        cmd = ["bash", os.path.join(HERE, "harness.sh"), "--cases", self.scn.cases_file, *extra]
        p = subprocess.Popen(cmd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                             pass_fds=(show_fd,) if show_fd is not None else ())
        lines = []
        for line in p.stdout:
            lines.append(line)
            if on_row:
                on_row(line)
        err = p.stderr.read().strip()
        if err:
            print(err, file=sys.stderr)
        rc = p.wait()
        shutil.rmtree(home, ignore_errors=True)
        return rc, "".join(lines)

    def cases(self):
        rc, out = self.run(["--list"])
        return [tuple(line.split("\t")) for line in out.splitlines() if line.count("\t") == 2]


def forward_renders(viewer):
    """A pipe the harness writes every rendered result to; a thread copies it into the viewer window (a terminal wants CRLF).
    Returns the write end's fd (to hand to the harness)."""
    r, w = os.pipe()

    def pump():
        with os.fdopen(r, "rb", buffering=0) as src:
            while True:
                chunk = src.read(4096)
                if not chunk:
                    return
                viewer.write(chunk.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))

    threading.Thread(target=pump, daemon=True).start()
    return w


def parse_row(line):
    f = line.rstrip("\n").split("\t")
    if len(f) != 9:
        return None
    cid, renderer, dataset, args, budget, calls, samples, nbytes, forks = f
    return {"id": cid, "renderer": renderer, "dataset": dataset, "args": args, "budget_ms": float(budget), "calls": int(calls),
            "ms": [int(x) / 1000.0 for x in samples.split(",") if x], "bytes": int(nbytes), "forks": int(forks)}


def merge_rounds(rounds):
    """Rows of every round -> {renderer: [case]} in case order; a case's samples and calls add up over the rounds."""
    merged = collections.OrderedDict()
    for rows in rounds:
        for r in rows:
            if r["id"] in merged:
                merged[r["id"]]["ms"] += r["ms"]
                merged[r["id"]]["calls"] += r["calls"]
            else:
                merged[r["id"]] = dict(r, ms=list(r["ms"]))
    out = collections.OrderedDict()
    for r in merged.values():
        out.setdefault(r["renderer"], []).append(r)
    return out


def step_result(r):
    """The LiveUI line of one finished case: its median against the renderer's budget, plus output size and forks."""
    return {"group": r["renderer"], "ok": True, "settle_ms": med(r["ms"]),
            "extra": [f"p95 {pct(r['ms'], 95):.1f} ms", f"{r['bytes']} bytes", f"{r['forks']} forks", f"{r['calls']} calls"]}


def build_report(cases, meta, baseline, attr=None):
    """The profiler's results shape (reporting/README.md): one group per renderer, one detail per case."""
    groups = []
    for renderer, rows in cases.items():
        details = [{"detail": f"{r['dataset']} · {r['args']}", "settle": med(r["ms"]), "p95": pct(r["ms"], 95), "bytes": r["bytes"], "forks": r["forks"],
                    "calls": r["calls"]} for r in rows]
        g = group(renderer, renderer, [d["settle"] for d in details], rows[0]["budget_ms"], kind="render", details=details,
                  bytes_=[d["bytes"] for d in details])
        g["forks"] = sum(d["forks"] for d in details)
        groups.append(g)
    rep = {"meta": meta, "latency": groups, "compare": compare_groups(groups, baseline) if baseline else None}
    if attr:
        rep["attr"] = attr
    return rep


def attribute(trace_dir, medians):
    """Where the time goes inside the renderers, from one xtrace per case (harness.sh --trace): wall time between two trace lines belongs to
    the earlier line; the traced time of every case is rescaled to that case's measured median (xtrace inflates in-shell time), then
    the cases average. Returns {"functions": [...], "hot_lines": [...]} in the shape of the profiler's attribution."""
    try:
        ids = open(os.path.join(trace_dir, "ids")).read().split("\n")
        functions = set(open(os.path.join(trace_dir, "functions")).read().split())
    except OSError:
        return None
    selfms, inclms, calls = collections.Counter(), collections.Counter(), collections.Counter()
    line_ms, line_hits, line_code, line_prog = collections.Counter(), collections.Counter(), {}, collections.Counter()
    n = 0
    for i, cid in enumerate(i for i in ids if i):
        try:
            raw = open(os.path.join(trace_dir, f"{i}.trace"), errors="replace").read().splitlines()
        except OSError:
            continue
        recs = []
        for ln in raw:
            if not ln.startswith("@"):
                continue
            head, _, code = ln.partition("| ")
            try:
                ts, src, stack = head[1:].split("|", 2)
            except ValueError:
                continue
            if ts.isdigit():
                recs.append((int(ts), src, stack.split(), code.strip()))
        if len(recs) < 2 or not medians.get(cid):
            continue
        gaps = [recs[j + 1][0] - recs[j][0] for j in range(len(recs) - 1)]
        total = sum(gaps)
        if total <= 0:
            continue
        k = medians[cid] / (total / 1000.0)   # traced µs -> measured ms
        n += 1
        prev = None
        for (ts, src, stack, code), gap in zip(recs, gaps):
            ms = gap / 1000.0 * k
            top = stack[0] if stack else "main"
            selfms[top] += ms
            for f in set(stack) or {"main"}:
                inclms[f] += ms
            if top != prev:
                calls[top] += 1
            prev = top
            word = code.split(" ", 1)[0] if code else ""
            line_ms[src] += ms
            line_hits[src] += 1
            line_code.setdefault(src, code[:90])
            if word and word not in functions and word not in BUILTINS and "=" not in word and shutil.which(word):
                line_prog[src] += ms
    if not n:
        return None
    fns = [{"name": f, "self_ms": selfms[f] / n, "incl_ms": inclms[f] / n, "calls": calls[f] / n, "per_call_us": selfms[f] / max(calls[f], 1) * 1000, "layer": "render"}
           for f in selfms]
    fns.sort(key=lambda x: -x["self_ms"])
    lines = [{"src": s, "ms": line_ms[s] / n, "hits": line_hits[s] / n, "code": line_code[s], "ex_ms": line_prog[s] / n, "fk_ms": 0.0} for s in line_ms]
    lines.sort(key=lambda x: -x["ms"])
    return {"functions": fns[:30], "hot_lines": lines[:30], "cases_traced": n}


def previous(path):
    try:
        with open(os.path.join(path, "report.json") if os.path.isdir(path) else path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def choose_scenario(scn):
    """Numbered menu on stdin/stdout; Enter = 1 (everything)."""
    c = term.c
    print()
    print(f" {c('◆', 'cyan', bold=True)} {c('Which scenario?', 'white', bold=True)}  {c('type a number (several allowed: 2,7), Enter = 1', 'dim')}\n")
    for i, (name, desc, _) in enumerate(scn.scenarios, 1):
        print(f"   {c(str(i), 'cyan', bold=True)}  {c(f'{name:<10}', 'white')} {c(desc, 'dim')}")
    print()
    try:
        return input(f" {c('›', 'cyan', bold=True)} ").strip() or "1"
    except (EOFError, KeyboardInterrupt):
        print()
        sys.exit(130)


def split_ids(ids, jobs):
    """IDS into JOBS lists, whole renderers together (so a unit is one renderer family), balanced by case count."""
    by = collections.OrderedDict()
    for cid in ids:
        by.setdefault(cid.split("/", 1)[0], []).append(cid)
    bins = [[] for _ in range(max(1, jobs))]
    for fam in sorted(by.values(), key=len, reverse=True):
        min(bins, key=len).extend(fam)
    return [b for b in bins if b]


def main():
    ap = argparse.ArgumentParser(description="Profile the renderers of lib/terminal_renderer.sh.")
    ap.add_argument("--quick", action="store_true", help="1 round, 8 calls per case (~30 s)")
    ap.add_argument("--deep", action="store_true", help="5 rounds (several minutes)")
    ap.add_argument("--rounds", type=int, help="measuring rounds, their samples add up (default 1)")
    ap.add_argument("--size", help="the renderers' width in columns: COLS or COLSxROWS (default 100)")
    ap.add_argument("--jobs", type=int, default=1, metavar="N", help="run N groups of renderers side by side (faster, but they compete for the machine)")
    ap.add_argument("--watch", action="store_true", help="show what the renderers draw in a second terminal window while it runs (shared viewer: reporting/watch.py); "
                                                         "writing to the window costs a little per case, so do not compare timings of watched runs")
    ap.add_argument("--wait", type=float, default=None, metavar="SECONDS", help="with --watch: seconds each rendered result stays on screen before the next case (default 0)")
    ap.add_argument("--trace", action="store_true", help="after the run, trace one call of every case to show where the time goes inside the renderers "
                                                         "(off by default: xtrace is slow)")
    ap.add_argument("--set", action="append", default=[], metavar="NAME=VALUE", help="option for the scenario file (repeatable): calls=N, width=N, wait=SECONDS")
    ap.add_argument("--compare", metavar="REPORT", help="report.json (or run dir) to diff against; default: the latest run")
    ap.add_argument("--no-compare", action="store_true")
    ap.add_argument("--report", metavar="REPORT", help="do not run anything: re-render an existing report.json / run dir")
    ap.add_argument("--scenario", metavar="NAME|N[,..]", help="what to run: a name or number from --list-scenarios, comma separated for several "
                                                               "(default: ask when interactive, else full)")
    ap.add_argument("--list-scenarios", action="store_true", help="print the scenarios and exit")
    ap.add_argument("--scenarios", default="renderers", metavar="FILE|NAME", help="scenario file the run is based on: a path, or a name in "
                    "tools/benchmarks/renderers/scenarios/ (default: renderers)")
    ap.add_argument("--out", metavar="OUT", help="output directory (default: tools/benchmarks/renderers/reports/<timestamp>)")
    ap.add_argument("--no-deep-dive", action="store_true", help="terminal report: the scorecard only, no per-case tables")
    ap.add_argument("--no-color", action="store_true")
    ap.add_argument("--plain", action="store_true", help="headless output: no live footer, no cursor control, no colour")
    ap.add_argument("--width", type=int, help="report width in columns")
    ap.add_argument("--events", metavar="FILE", help="append machine-readable progress (one JSON object per line) to FILE")
    a = ap.parse_args()
    term.init(False if (a.no_color or a.plain) else None)
    W = a.width or term.width()
    scn = Scenarios(a.scenarios)
    scn.set_options(a.set)
    if a.size:
        scn.options["width"] = a.size.split("x")[0]
    if a.wait is not None:
        scn.options["wait"] = str(a.wait)
    harness = Harness(scn, scn.options["width"])

    if a.report:
        rep = previous(a.report)
        if not rep:
            print(f"no report in {a.report}", file=sys.stderr)
            return 2
        print("\n".join(default_reporter.render(rep, W, details=not a.no_deep_dive)))
        return 0
    rows = harness.cases()
    if a.list_scenarios:
        c = term.c
        for i, (name, desc, _) in enumerate(scn.scenarios, 1):
            n = len(scn.resolve(name, rows)[1])
            print(f"  {c(str(i), 'cyan', bold=True):>3}  {c(f'{name:<9}', 'white')} {c(f'{n:>4} cases', 'dim')}  {c(desc, 'dim')}")
        return 0
    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    spec = a.scenario if a.scenario is not None else (choose_scenario(scn) if interactive else "full")
    try:
        picked, ids = scn.resolve(spec, rows)
    except ValueError as e:
        print(f"profile.sh: {e}", file=sys.stderr)
        return 2
    if not ids:
        print("profile.sh: the scenario selects no cases", file=sys.stderr)
        return 2

    rounds = a.rounds or (5 if a.deep else 1)
    quick = a.quick
    trace = a.trace
    calls = int(scn.options.get("calls") or 0)
    base_args = (["--quick"] if quick else []) + (["--calls", str(calls)] if calls else [])
    t0 = time.time()
    latest = os.path.join(REPORTS, "latest")
    baseline = None if a.no_compare else (previous(a.compare) if a.compare else (previous(latest) if os.path.exists(latest) else None))
    show_fd = None
    if a.watch:
        from reporting import watch
        show_fd = forward_renders(watch.Watch(WATCH_ROWS, WATCH_COLS))

    tmp = tempfile.mkdtemp(prefix="dabt-renderers-run-")
    units = split_ids(ids, a.jobs)
    for i, unit in enumerate(units):
        with open(os.path.join(tmp, f"ids{i}"), "w") as f:
            f.write("\n".join(unit) + "\n")
    budgets = {}
    live = LiveUI([("render", "Rendering", 1, len(ids) * rounds)], tty=False if a.plain else None, events=a.events,
                  info_of=lambda renderer: (renderer, "render", budgets.get(renderer, DEFAULT_BUDGET_MS)))
    live.begin([f" {term.c('◆', 'cyan', bold=True)} {term.c(scn.title, 'white', bold=True)}  "
                f"{term.c(f'{len(ids)} cases · {rounds} round' + ('s' if rounds != 1 else '') + f' · scenario {chr(44).join(picked)} · ' + ('quick' if quick else 'full'), 'dim')}",
                f" {term.c(f'lib/terminal_renderer.sh · width {scn.options['width']} · each case warmed, then called up to ' + (str(calls) if calls else ('8' if quick else '40')) + ' times · budgets per call', 'dim')}"
                + (f" {term.c('· renders shown in a second window', 'dim')}" if a.watch else ""), ""])
    lock = threading.Lock()
    all_rounds = []

    def run_unit(round_no, i, unit):
        """One harness process over one unit's cases; each finished case is a line of the live view."""
        name = f"unit {i + 1}" if len(units) > 1 else None
        done = []
        got = []
        if name:
            with lock:
                live.unit_begin(name, len(unit))
        if not name:
            live.step_begin(unit[0])
        elif unit:
            with lock:
                live.unit_step_begin(name, unit[0])

        def on_row(line):
            r = parse_row(line)
            if not r:
                return
            got.append(r)
            with lock:
                budgets[r["renderer"]] = r["budget_ms"]
                if name:
                    live.unit_step_end(name, r["id"], step_result(r))
                    if len(got) < len(unit):
                        live.unit_step_begin(name, unit[len(got)])
                else:
                    live.step_end(r["id"], step_result(r))
                    if len(got) < len(unit):
                        live.step_begin(unit[len(got)])

        extra = base_args + ["--ids", os.path.join(tmp, f"ids{i}")]
        rc, _ = harness.run(extra, on_row, show_fd if not a.jobs > 1 else None)
        if name:
            with lock:
                live.unit_done(name)
        return rc, got

    status = 0
    try:
        for rnd in range(rounds):
            live.phase("render", f"round {rnd + 1}/{rounds}" if rounds > 1 else "", len(ids))
            with concurrent.futures.ThreadPoolExecutor(max_workers=len(units)) as pool:
                results = list(pool.map(lambda iu: run_unit(rnd, iu[0], iu[1]), enumerate(units)))
            status = status or max(rc for rc, _ in results)
            all_rounds.append([r for _, got in results for r in got])
        attr = None
        if trace:
            live.note("tracing one call of every case")
            tdir = os.path.join(tmp, "trace")
            harness.run(["--quick", "--calls", "1", "--trace", tdir, "--ids", _all_ids(tmp, ids)])
            merged_now = merge_rounds(all_rounds)
            medians = {r["id"]: med(r["ms"]) for rs in merged_now.values() for r in rs}
            attr = attribute(tdir, medians)
    finally:
        live.finish()
    cases = merge_rounds(all_rounds)
    if not cases:
        print("the harness produced no rows", file=sys.stderr)
        return 1
    meta = {"title": scn.title, "commit": git("rev-parse", "--short", "HEAD"), "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
            "dirty": bool(git("status", "--porcelain", "--", "lib")), "scenario": "watched" if a.watch else ",".join(picked) if picked != ["full"] else "full",
            "rounds": rounds, "duration_s": time.time() - t0, "when": datetime.now().strftime("%Y-%m-%d %H:%M"),
            "cases": sum(len(v) for v in cases.values()), "row_label": "renderer",
            "legend": "typical = median per call · budget = what one call may take inside a repaint",
            "method": ("bash harness: each case is warmed twice, then called up to 40 times (8 with --quick) per round; forks = processes one call starts (xtrace)"
                       + ("; where the time goes: one xtrace per case, rescaled to its measured median" if attr else "")
                       + ("; side by side with --jobs: the units compete for the machine" if a.jobs > 1 else "") + ".")}
    rep = build_report(cases, meta, baseline, attr)
    lines = default_reporter.render(rep, W, details=not a.no_deep_dive)
    print("\n".join(lines))
    out_dir = a.out or os.path.join(REPORTS, datetime.now().strftime("%Y%m%d-%H%M%S"))
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "report.json"), "w") as f:
        json.dump(rep, f, indent=1)
    with open(os.path.join(out_dir, "report.txt"), "w") as f:
        f.write(term.ANSI_RE.sub("", "\n".join(lines)) + "\n")
    if not a.out:
        try:
            if os.path.islink(latest) or os.path.exists(latest):
                os.remove(latest)
            os.symlink(os.path.basename(out_dir), latest)
        except OSError:
            pass
    print(f"\nsaved  {os.path.relpath(out_dir, REPO)}/  report.json · report.txt")
    print(f"again  tools/benchmarks/renderers/profile.sh --report {os.path.relpath(out_dir, REPO)}")
    shutil.rmtree(tmp, ignore_errors=True)
    return status


def _all_ids(tmp, ids):
    path = os.path.join(tmp, "ids_all")
    with open(path, "w") as f:
        f.write("\n".join(ids) + "\n")
    return path


if __name__ == "__main__":
    sys.exit(main())
