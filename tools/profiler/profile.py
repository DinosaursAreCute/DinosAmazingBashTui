#!/usr/bin/env python3
"""DABT profiler driver (started by profile.sh). See README.md."""
import argparse
import atexit
import json
import os
import subprocess
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import explore                                           # noqa: E402
from dprof import term                                  # noqa: E402
from dprof.analyze import build_report, med, pct        # noqa: E402
from dprof.live import LiveUI                           # noqa: E402
from dprof.runner import latency_round, traced_session  # noqa: E402
from dprof import scenarios                             # noqa: E402
from dprof.scenarios import SCENARIOS, resolve_scenarios, units   # noqa: E402
from dprof.session import REPO, kill_all                # noqa: E402
from dprof import report_term, report_html, sysinfo              # noqa: E402

REPORTS = os.path.join(HERE, "reports")


def parse():
    p = argparse.ArgumentParser(prog="profile.sh", description="End-to-end profiler for DABT apps.")
    p.add_argument("--quick", action="store_true", help="1 round, shortened script, warm trace only (~1.5 min)")
    p.add_argument("--deep", action="store_true", help="5 rounds and a traced cold start too (~10 min)")
    p.add_argument("--rounds", type=int, help="untraced latency rounds (default 2)")
    p.add_argument("--size", default=None, help="terminal COLSxROWS the app runs in (default: the scenario file's, 150x45)")
    p.add_argument("--jobs", type=int, default=1, metavar="N", help="run N independent units side by side (default 1; faster, but they compete for the machine and the timings show it)")
    p.add_argument("--no-trace", action="store_true", help="latency only: skip the xtrace attribution pass")
    p.add_argument("--trace", action="store_true", help="a sweep scenario runs latency only; this adds the xtrace attribution pass "
                   "(slow: it is 3x slower and a large rung produces a very large trace)")
    p.add_argument("--trace-runs", type=int, metavar="N", help="traced passes (default 1, or what the scenario wants: perflab's floor "
                   "5, --quick 1); their stacks add up, so per-action figures are means")
    p.add_argument("--set", action="append", default=[], metavar="NAME=VALUE",
                   help="option for the scenario file (repeatable): scale=0.5, or an axis ladder such as table.rows=1000,10000")
    p.add_argument("--cold-trace", action="store_true", help="also trace a cold start (2M+ lines, ~2 min)")
    p.add_argument("--compare", metavar="REPORT", help="report.json (or run dir) to diff against; default: the latest run")
    p.add_argument("--no-compare", action="store_true")
    p.add_argument("--report", metavar="REPORT", help="do not run anything: re-render an existing report.json / run dir")
    p.add_argument("--scenario", metavar="NAME|N[,..]",
                   help="what to run: a name or number from --list-scenarios, comma separated for several "
                        "(default: ask when interactive, else full)")
    p.add_argument("--list-scenarios", action="store_true", help="print the scenarios and exit")
    p.add_argument("--scenarios", metavar="FILE|NAME", help="scenario file the run is based on: a path, or a name in "
                   "tools/profiler/scenarios/ (default: demo)")
    p.add_argument("--app", help="app script to profile (default: the scenario file's APP, bin/DABT_demo.sh for demo)")
    p.add_argument("--out", help="output directory (default: tools/profiler/reports/<timestamp>)")
    p.add_argument("--no-html", action="store_true")
    p.add_argument("--open", action="store_true", help="open report.html when done")
    p.add_argument("--no-deep-dive", action="store_true", help="terminal report: overview only")
    p.add_argument("--no-color", action="store_true")
    p.add_argument("--plain", action="store_true",
                   help="headless output: no live footer, no cursor control, no colour; with --jobs each finished unit is "
                        "printed as one block (also the behaviour whenever stdout is not a terminal)")
    p.add_argument("--width", type=int)
    a = p.parse_args()
    try:   # before the size is read: a scenario file may set the terminal size
        scenarios.set_options(a.set)
        scenarios.load(a.scenarios)
    except (scenarios.ScenarioFileError, ValueError) as e:
        p.error(str(e))
    cols, _, rows = (a.size or scenarios.DEFAULTS["size"]).lower().partition("x")
    a.cols, a.rows = int(cols), int(rows or 45)
    a.rounds_given = a.rounds is not None
    if a.rounds is None:
        a.rounds = 1 if a.quick else 5 if a.deep else 2
    if a.deep:
        a.cold_trace = True
    return a


def sh(*cmd):
    try:
        return subprocess.check_output(cmd, cwd=REPO, stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def load_report(path):
    if os.path.isdir(path):
        path = os.path.join(path, "report.json")
    with open(path) as f:
        return json.load(f)


def latest_report():
    p = os.path.join(REPORTS, "latest", "report.json")
    return p if os.path.exists(p) else None


class Cfg:
    pass


def choose_scenario():
    """Numbered menu on stdin/stdout; Enter = everything."""
    c = term.c
    print()
    print(f" {c('◆', 'cyan', bold=True)} {c('Which scenario?', 'white', bold=True)}  "
          f"{c('type a number (several allowed: 2,7), Enter = 1', 'dim')}")
    print()
    for i, (name, desc, _) in enumerate(SCENARIOS, 1):
        print(f"   {c(str(i), 'cyan', bold=True)}  {c(f'{name:<10}', 'white')} {c(desc, 'dim')}")
    print()
    while True:
        try:
            ans = input(f" {c('›', 'cyan', bold=True)} ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            sys.exit(130)
        try:
            return ans or "1"
        finally:
            pass


def main():
    a = parse()
    term.init(False if (a.no_color or a.plain) else None)
    W = a.width or term.width()

    if a.list_scenarios:
        for i, (name, desc, _) in enumerate(SCENARIOS, 1):
            print(f"{i}  {name:<10} {desc}")
        return 0

    if a.report:
        rep = load_report(a.report)
        print("\n".join(report_term.render(rep, W, deep=not a.no_deep_dive)))
        return 0

    if sys.version_info < (3, 8):
        print("needs python >= 3.8", file=sys.stderr)
        return 2
    if not os.path.exists(os.path.join(REPO, "lib", "tui.sh")):
        print(f"not a DABT checkout: {REPO}", file=sys.stderr)
        return 2
    atexit.register(kill_all)

    spec = a.scenario
    if spec is None:
        spec = choose_scenario() if (sys.stdin.isatty() and sys.stdout.isatty()) else "full"
    while True:
        try:
            scenario_names, wanted = resolve_scenarios(spec)
            break
        except ValueError as e:
            if a.scenario is not None or not sys.stdin.isatty():
                print(f"profile.sh: {e}", file=sys.stderr)
                return 2
            print(f" {term.c(str(e), 'red')}")
            spec = choose_scenario()

    sweep = bool(scenario_names) and all(n in scenarios.SWEEP for n in scenario_names)
    if sweep and not a.trace:
        a.no_trace = True   # a sweep climbs to sizes the xtrace pass cannot follow; --trace asks for it anyway
    trace_runs = 1
    run = scenarios.RUNS.get(scenario_names[0]) if len(scenario_names) == 1 else None
    if run:   # a scenario that wants its own number of passes (quick: one, like the demo's quick run)
        trace_runs = run["quick_trace_runs"] if a.quick else run["trace_runs"]
        if not a.rounds_given:
            a.rounds = run["quick_rounds"] if a.quick else run["rounds"]
    if a.trace_runs:
        trace_runs = max(1, a.trace_runs)
    scenarios.prepare(wanted)
    cfg = Cfg()
    cfg.wanted = wanted
    cfg.rows, cfg.cols, cfg.quick, cfg.rounds = a.rows, a.cols, a.quick, a.rounds
    cfg.start_timeout, cfg.hints, cfg.app, cfg.jobs = 120, {}, a.app, max(1, a.jobs)
    todo = units(cfg.rows, cfg.cols, cfg.quick, wanted)
    per_round = sum(len(u.steps) + 1 for u in todo) + 2
    phases = [("latency", "Latency", 1, per_round * cfg.rounds)]
    if not a.no_trace:
        phases.append(("trace", "Attribution trace", 2.5, per_round * trace_runs))
        if a.cold_trace and (wanted is None or "startup.cold" in wanted):
            phases.append(("cold", "Cold-start trace", 60, 1))
    phases += [("analyze", "Analysis", 2, 1), ("report", "Report", 2, 1)]

    commit, branch = sh("git", "rev-parse", "--short", "HEAD"), sh("git", "rev-parse", "--abbrev-ref", "HEAD")
    dirty = bool(sh("git", "status", "--porcelain", "--untracked-files=no"))
    t_start = time.time()
    live = LiveUI(phases, tty=False if a.plain else None)
    mode = "quick" if a.quick else "deep" if a.deep else "standard"
    live.begin([
        "",
        f" {term.c('◆', 'cyan', bold=True)} {term.c('DABT PROFILER', 'white', bold=True)}  "
        f"{term.c(f'{commit} {branch}' + (' +local changes' if dirty else ''), 'dim')}",
        f" {term.c(f'{mode} run · {cfg.cols}×{cfg.rows} terminal · {cfg.rounds} latency round(s)' + ('' if a.no_trace else ' · call-stack trace') + (' · cold trace' if a.cold_trace else ''), 'dim')}",
        f" {term.c('real app in a hidden pty · latency from in-app probes · call graph from bash xtrace', 'faint')}",
        "",
    ])

    rounds, traces, warnings = [], [], []
    machine = sysinfo.machine(cfg.rows, cfg.cols)
    sampler = sysinfo.Sampler().start()
    try:
        for i in range(cfg.rounds):
            live.phase("latency", f"round {i + 1}/{cfg.rounds}", per_round)
            r = latency_round(cfg, live, i, sampler)
            rounds.append(r)
            warnings += r.get("warnings", [])
        # how long an action needs untraced tells the traced run how long to wait for it
        by = {}
        for r in rounds:
            for x in r["actions"]:
                if x.get("settle_ms") is not None:
                    by.setdefault(x["group"], []).append(x["settle_ms"] / 1000)
            for k, tl in r["startup"].items():
                if tl.get("ready_ms"):
                    by.setdefault("startup." + k, []).append(tl["ready_ms"] / 1000)
        cfg.hints = {g: pct(v, 95) for g, v in by.items()}
        if not a.no_trace:
            for i in range(trace_runs):
                live.phase("trace", f"warm session {i + 1}/{trace_runs}" if trace_runs > 1 else "warm session")
                traces += traced_session(cfg, live, cold=False)
            warnings += [w for t in traces for w in t.get("warnings", [])]
            if a.cold_trace and (wanted is None or "startup.cold" in wanted):
                live.phase("cold", "empty cache")
                traces += traced_session(cfg, live, cold=True)
        live.phase("analyze")
        meta = {"when": datetime.now().strftime("%Y-%m-%d %H:%M"), "commit": commit, "branch": branch, "dirty": dirty,
                "rows": cfg.rows, "cols": cfg.cols, "rounds": cfg.rounds, "mode": mode, "scenario": ",".join(scenario_names), "warnings": sorted(set(warnings)),
                "scenarios_file": scenarios.SOURCE["name"], "sweep": sweep, "trace_runs": trace_runs,
                "groups_run": None if wanted is None else sorted(wanted), "options": dict(scenarios.OPTIONS), "duration_s": time.time() - t_start, "traced": not a.no_trace, "jobs": cfg.jobs, "machine": machine,
                "load": sampler.summary(t_start, time.time())}
        base = None
        if not a.no_compare:
            bp = a.compare or latest_report()
            if bp and os.path.exists(bp if not os.path.isdir(bp) else os.path.join(bp, "report.json")):
                base = load_report(bp)
        rep = build_report(meta, rounds, traces, base)
        live.phase("report")
        out = a.out or os.path.join(REPORTS, datetime.now().strftime("%Y%m%d-%H%M%S"))
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "report.json"), "w") as f:
            json.dump(rep, f, default=str)
        txt = report_term.render(rep, 140)
        with open(os.path.join(out, "report.txt"), "w") as f:
            f.write(term.ANSI_RE.sub("", "\n".join(txt)) + "\n")
        html_path = None
        if not a.no_html:
            html_path = os.path.join(out, "report.html")
            with open(html_path, "w") as f:
                f.write(report_html.render(rep))
        if not a.out:
            try:
                explore.update()   # the explorer sees every new run without being told
            except OSError:
                pass
            latest = os.path.join(REPORTS, "latest")
            try:
                if os.path.islink(latest) or os.path.exists(latest):
                    os.remove(latest)
                os.symlink(os.path.basename(out), latest)
            except OSError:
                pass
    except KeyboardInterrupt:
        live.finish()
        kill_all()
        print("\naborted.", file=sys.stderr)
        return 130
    finally:
        sampler.stop()
        live.finish()

    print()
    print("\n".join(report_term.render(rep, W, deep=not a.no_deep_dive)))
    print()
    rel = os.path.relpath(out, os.getcwd())
    print(f" {term.c('saved', 'dim')}  {term.c(rel + '/', 'cyan')}  "
          f"{term.c('report.html · report.json · report.txt', 'dim')}")
    print(f" {term.c('again', 'dim')}  {term.c('tools/profiler/profile.sh --report ' + rel, 'dim')}"
          f"   {term.c('total', 'dim')} {term.c(f'{time.time() - t_start:.0f}s', 'dim')}")
    if a.open and html_path:
        subprocess.Popen(["xdg-open", html_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
