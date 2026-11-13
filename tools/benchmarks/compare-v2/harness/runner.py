"""Orchestration. Per round and app: cold start (fresh HOME) -> warm start (same HOME, caches built) -> the scenario.

Good-practice choices made here:
  * warm-up rounds run first and are discarded (page cache, .pyc, CPU frequency)
  * apps alternate within every round and their order is shuffled per round, so drift (thermal, background load) hits both equally
  * each run is a fresh process in a fresh HOME; nothing but the temp dir survives between rounds
  * app and harness are pinned to different physical cores
  * the terminal answers capability queries like a modern terminal, so no app waits on a reply that never comes"""
import os
import random
import shutil
import tempfile
import time
import traceback

from .expect import as_expect
from .measure import Run
from .scenario import Ctx


def make_env(home):
    env = dict(os.environ, HOME=home, TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8", LANG="C.UTF-8")
    for k in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "TUI_HOME", "COLUMNS", "LINES", "NO_COLOR"):
        env.pop(k, None)
    env["XDG_CONFIG_HOME"] = os.path.join(home, ".config")
    os.makedirs(env["XDG_CONFIG_HOME"], exist_ok=True)
    return env


def ready_for(scn, app):
    r = scn.ready.get(app.name) if isinstance(scn.ready, dict) else scn.ready
    return as_expect(r)


def start(app, home, scn, cpus, quiet, replies, max_timeout=None, keyboard="auto"):
    env = {**make_env(home), **app.env}
    run = Run(app.argv(home), env, home, scn.rows, scn.cols, cpus, quiet, replies, keyboard)
    run.max_timeout = max_timeout
    return run


def timed(rep, app, rnd, results, name, fn):
    """Runs one startup measurement and reports it like a scenario step."""
    if rep:
        rep.step_begin(name)
    r = fn()
    r["name"] = name
    results.append(r)
    if rep:
        rep.step_end(app.name, rnd, r)


def run_round(app, scn, cpus, quiet, replies, snaps, rep=None, rnd=0, max_timeout=None, keyboard="auto"):
    """One round for one app. Returns the list of result dicts (startup.cold, startup.warm, scenario steps)."""
    home = tempfile.mkdtemp(prefix=f"cmp2-{app.name}-")
    out = []
    try:
        if app.prepare:
            app.prepare(home)
        ready = ready_for(scn, app)
        run = start(app, home, scn, cpus, quiet, replies, max_timeout, keyboard)
        timed(rep, app, rnd, out, "startup.cold", lambda: run.startup(ready))
        out[-1]["keyboard"] = "kitty CSI-u" if run.sess.kitty_keys else "legacy ESC"
        if app.background_done:
            if rep:
                rep.step_begin("cache warm-up (untimed)")
            run.wait_for(app.background_done, 30)  # deferred work (cache warmup) must finish or the steps would race it
        run.close()
        run = start(app, home, scn, cpus, quiet, replies, max_timeout, keyboard)
        timed(rep, app, rnd, out, "startup.warm", lambda: run.startup(ready))
        try:
            scn.fn(Ctx(run, app, out, snaps, rep, rnd))
        finally:
            run.close()
    finally:
        shutil.rmtree(home, ignore_errors=True)
    return out


def execute(apps, scn, rounds, warmup, cpus, quiet, replies, seed, rep=None, max_timeout=None, keyboard="auto"):
    """Runs the whole benchmark; `rep` is a reporter.Reporter. Returns (data, snapshots, step order, errors)."""
    data = {a.name: {} for a in apps}
    snaps = {a.name: {} for a in apps}
    order = []
    errors = []
    for rnd in range(-warmup, rounds):
        names = list(apps)
        random.Random(seed * 1000 + rnd).shuffle(names)
        for app in names:
            if rep:
                rep.round_start(app.name, rnd, rounds)
            t = time.perf_counter()
            try:
                results = run_round(app, scn, cpus, quiet, replies, snaps[app.name] if rnd == 0 else {}, rep, rnd, max_timeout, keyboard)
            except Exception:  # a crashing app must not lose the other rounds
                errors.append({"app": app.name, "round": rnd, "error": traceback.format_exc()})
                if rep:
                    rep.round_end(app.name, time.perf_counter() - t, errors[-1]["error"].strip().splitlines()[-1])
                continue
            if rep:
                rep.round_end(app.name, time.perf_counter() - t)
            if rnd < 0:
                continue
            for r in results:
                data[app.name].setdefault(r["name"], []).append({**r, "round": rnd})
                if not any(o["name"] == r["name"] for o in order):
                    order.append({"name": r["name"], "kind": r["kind"]})
    return data, snaps, order, errors
