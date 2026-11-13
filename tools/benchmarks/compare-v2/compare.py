#!/usr/bin/env python3
"""compare-v2: screen-accurate, statistically sound benchmarking of terminal apps (DABT vs Textual and friends).

  compare.py run [SCENARIO...]            run (default scenario: session); then print + save the report
  compare.py report RESULTS.json          re-render a saved run
  compare.py selftest                     check the harness itself against an app with known delays (~15 s)
  compare.py list                         scenarios and apps

  compare.py run session --rounds 10 --apps dabt,textual --size 150x45
  compare.py run quick --rounds 3 --warmup 0            # smoke test
  compare.py run quick --watch --rounds 1 --warmup 0    # look at what the apps draw
  compare.py --plugins ./my_dir run                     # extra scenarios/apps (any .py with @scenario / register())

Needs `rich` and `pyte`; re-executes itself with $COMPARE_VENV (default ~/.cache/dabt-compare-venv) if they are missing here."""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
VENV = os.environ.get("COMPARE_VENV", os.path.expanduser("~/.cache/dabt-compare-venv"))
try:
    import pyte  # noqa: F401
    import rich  # noqa: F401
except ImportError:
    py = os.path.join(VENV, "bin", "python")
    if os.path.exists(py) and os.path.realpath(sys.prefix) != os.path.realpath(VENV):
        os.execv(py, [py, *sys.argv])
    sys.exit(f"needs rich + pyte:  python3 -m venv {VENV} && {VENV}/bin/pip install rich pyte textual")

from harness import apps as apps_mod, loader, report_html, report_term, reporter, runner, scenario as scn_mod, stats, sysinfo, term, watch  # noqa: E402
from harness.governor import Performance  # noqa: E402
from harness.inhibit import KeepAwake  # noqa: E402


def load_plugins(extra):
    loader.load_dir(os.path.join(HERE, "apps"))
    loader.load_dir(os.path.join(HERE, "scenarios"))
    for d in extra:
        loader.load_dir(d)


def cmd_list(_):
    print("scenarios:")
    for s in scn_mod.SCENARIOS.values():
        print(f"  {s.name:<12} {s.title}  [default apps: {', '.join(s.default_apps) or 'dabt, textual'}]")
    print("apps:")
    for a in apps_mod.APPS.values():
        print(f"  {a.name:<12} {a.label}")


def cmd_selftest(a):
    """Runs the calibration scenario and checks measured vs nominal response time."""
    import re
    from rich.console import Console
    from rich.table import Table
    scn = scn_mod.SCENARIOS["calibration"]
    app_cpus, harness_cpus = sysinfo.pick_pinning("auto")
    if harness_cpus:
        os.sched_setaffinity(0, harness_cpus)
    with KeepAwake("compare-v2 selftest"):
        data, _, order, _ = runner.execute([apps_mod.APPS["calib"]], scn, 3, 0, app_cpus, 0.15, True, 1)
    con, ok_all = Console(), True
    t = Table(title="harness self-check (reference app with known delays)", title_justify="left")
    for col in ("step", "nominal ms", "measured median", "error", "p95 error", "paints", "verdict"):
        t.add_column(col, justify="right" if col != "step" else "left")
    for st in order:
        m = re.match(r"(?:delay|sync|multi)\.(\d+)ms", st["name"])
        if not m:
            continue
        rows = [s for s in data["calib"][st["name"]] if s["ok"]]
        err = sorted(s["ready_ms"] - int(m.group(1)) for s in rows)
        med, p95 = stats.quantile(err, .5), stats.quantile(err, .95)
        paints = max((s["paints"] for s in rows), default=0)
        ok = bool(rows) and -0.3 <= med <= 1.5 and p95 <= 3.0 and (not st["name"].startswith("sync") or paints == 1)
        ok_all &= ok
        t.add_row(st["name"], m.group(1), f"{med + int(m.group(1)):.2f}", f"{med:+.2f}", f"{p95:+.2f}", str(paints), "[green]ok[/]" if ok else "[red]FAIL[/]")
    con.print(t)
    con.print("[dim]error = measured - nominal: constant offset is the harness+pty bias, p95 its jitter. sync.30ms must show exactly 1 paint (half-frame hidden).[/]")
    sys.exit(0 if ok_all else 1)


def cmd_report(a):
    with open(a.results) as f:
        res = json.load(f)
    emit(res, os.path.dirname(os.path.abspath(a.results)), a.no_html, reporter.ConsoleReporter(False, stream=sys.stdout))


def emit(res, out, no_html, rep):
    m = res["meta"]
    if m.get("watched") and not m.get("skew"):  # a report written before skew was recorded
        m["skew"] = ["--watch mirrors every output chunk into a viewer window: timings of this run are NOT comparable."]
    an = stats.analyze(res)
    rep.run_end(res, an)
    with open(os.path.join(out, "report.txt"), "w") as f:
        report_term.render(res, an, file=f, plain=True)
    if not no_html:
        with open(os.path.join(out, "report.html"), "w") as f:
            f.write(report_html.render(res, an))
    print(f"\nsaved {out}", file=sys.stderr)


def cmd_run(a):
    with Performance() as gov:  # governor -> performance for the whole run; restored on any exit
        _run(a, gov)


def _run(a, gov):
    cols, rows = (int(x) for x in a.size.split("x")) if a.size else (None, None)
    for name in a.scenario or ["session"]:
        if name not in scn_mod.SCENARIOS:
            sys.exit(f"unknown scenario {name!r}; try: compare.py list")
        scn = scn_mod.SCENARIOS[name]
        if cols:
            scn.rows, scn.cols = rows, cols
        # --apps overrides the scenario's own default apps, which override the global default
        names = a.apps.split(",") if a.apps else list(scn.default_apps) or [n for n in ("dabt", "textual") if n in apps_mod.APPS]
        for n in names:
            if n not in apps_mod.APPS:
                sys.exit(f"unknown app {n!r}; try: compare.py list")
        apps = [apps_mod.APPS[n] for n in names]
        if scn.apps and any(x.name not in scn.apps for x in apps):
            sys.exit(f"scenario {scn.name!r} only supports apps: {', '.join(scn.apps)}")
        app_cpus, harness_cpus = sysinfo.pick_pinning(a.pin)
        if harness_cpus:
            os.sched_setaffinity(0, harness_cpus)
        info, warnings = sysinfo.collect(os.path.abspath(os.path.join(HERE, "..", "..", "..")), app_cpus, harness_cpus)
        if a.rounds < 8:
            warnings.append(f"only {a.rounds} measured rounds: confidence intervals are rough below ~8.")
        if a.watch:
            term.WATCH = watch.open_viewer(scn.rows, scn.cols)
            warnings.append("--watch mirrors every output chunk into a viewer window: timings of this run are NOT comparable.")
        warnings_skew = [w for w in warnings if not w.startswith("only ")]  # machine noise, pinning, --watch: everything except "few rounds" (that one widens the CIs, it does not skew)
        if gov.note:
            warnings.append(f"CPU governor not set to performance: {gov.note}.")
        rep = reporter.make(a.reporter, a.events)
        meta = {"scenario": scn.name, "title": scn.title, "rows": scn.rows, "cols": scn.cols, "rounds": a.rounds, "warmup": a.warmup,
                "apps": [{"name": x.name, "label": x.label, "color": x.color, "version": x.version() if x.version else ""} for x in apps]}
        rep.run_start(meta)
        for w in warnings:
            rep.warn(w)
        started = time.time()
        with KeepAwake(f"compare-v2 benchmark: {scn.name}") as awake:
            if not awake.ok:
                warnings_skew.append("could not inhibit sleep and screen blanking (systemd-inhibit missing or refused): the machine may sleep or dim during the run.")
                rep.warn(warnings_skew[-1])
            data, snaps, order, errors = runner.execute(apps, scn, a.rounds, a.warmup, app_cpus, a.quiet_ms / 1000, not a.no_replies, a.seed, rep, a.step_timeout, a.keyboard)
        for x in meta["apps"]:  # which key encoding each app actually received
            first = (data.get(x["name"], {}).get("startup.cold") or [{}])[0]
            x["keyboard"] = first.get("keyboard", "")
        skew = list(warnings_skew)
        if a.keyboard == "legacy":
            skew.append("--keyboard legacy: every app got ESC-prefixed alt keys, which costs Textual an escape wait it does not pay in a kitty-protocol terminal.")
        res = {"meta": {**meta, "skew": skew, "keyboard_mode": a.keyboard, "keep_awake": awake.ok, "quiet_ms": a.quiet_ms, "seed": a.seed, "watched": bool(a.watch),
                        "started": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(started)),
                        "duration_s": round(time.time() - started, 1), "env": info, "warnings": warnings, "errors": errors},
               "steps": order, "data": data, "snapshots": snaps}
        out = a.out or os.path.join(HERE, "reports", f"{time.strftime('%Y%m%d-%H%M%S')}-{scn.name}")
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "results.json"), "w") as f:
            json.dump(res, f, indent=1)
        emit(res, out, a.no_html, rep)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plugins", action="append", default=[], metavar="DIR", help="extra directory of scenario/app .py files (repeatable)")
    sub = ap.add_subparsers(dest="cmd")
    r = sub.add_parser("run")
    r.add_argument("scenario", nargs="*")
    r.add_argument("--apps", help="comma list, first = baseline (default: the scenario's own apps, else dabt,textual)")
    r.add_argument("--rounds", type=int, default=8, help="measured rounds per app (default 8)")
    r.add_argument("--warmup", type=int, default=1, help="discarded warm-up rounds (default 1)")
    r.add_argument("--size", help="COLSxROWS (default: the scenario's, 150x45)")
    r.add_argument("--quiet-ms", type=int, default=150, help="output silence that ends a step (never part of a reported time)")
    r.add_argument("--pin", default="auto", help="auto (harness on its own core, app on the rest) | single (app on one core) | none | APPCPUS:HARNESSCPUS e.g. 0-9:10,11")
    r.add_argument("--seed", type=int, default=1, help="order shuffling + bootstrap seed")
    r.add_argument("--step-timeout", type=float, help="cap every step's wait at this many seconds (quick debugging runs)")
    r.add_argument("--keyboard", choices=("auto", "legacy"), default="auto",
                   help="auto: modified keys follow what each app asked for (kitty CSI-u or legacy ESC prefix); legacy: always ESC prefix")
    r.add_argument("--no-replies", action="store_true", help="the terminal never answers capability queries (DA, DECRQM)")
    r.add_argument("--no-html", action="store_true")
    r.add_argument("--reporter", choices=("live", "plain", "none"), default="live", help="live: log + footer (falls back to plain without a tty)")
    r.add_argument("--events", metavar="FILE", help="also append machine-readable progress (JSON lines) to FILE")
    r.add_argument("--watch", action="store_true", help="show the app live in a second window of the test size (timings are then not comparable)")
    r.add_argument("--out")
    p = sub.add_parser("report")
    p.add_argument("results")
    p.add_argument("--no-html", action="store_true")
    sub.add_parser("list")
    sub.add_parser("selftest")
    a = ap.parse_args()
    load_plugins(a.plugins)
    {"run": cmd_run, "report": cmd_report, "list": cmd_list, "selftest": cmd_selftest, None: lambda x: ap.print_help()}[a.cmd](a)


if __name__ == "__main__":
    main()
