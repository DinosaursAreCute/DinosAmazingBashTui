"""Orchestrates profiler runs: latency rounds (untraced) and attribution runs (traced)."""
import os
import shutil
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from .scenarios import units
from .session import Session, WRAPPED, now
from .trace import Tracer


class NullUI:
    def phase(self, name, total=0, detail=""): pass
    def step_begin(self, desc): pass
    def step_end(self, desc, res): pass
    def note(self, text): pass
    def set_tracer(self, tracer): pass


def _first(sess, kind, name, after=0.0):
    for e in sess.events:
        if e.kind == kind and e.name == name and e.t0 >= after:
            return e
    return None


def startup_timeline(sess):
    """Phases of a start, in ms since spawn, from the app's own probe events."""
    t0 = sess.t_spawn
    ms = lambda t: (t - t0) * 1000
    spans = []
    boot = _first(sess, "E", "shim_start")
    if boot:
        spans.append(("bash + script boot", 0.0, ms(boot.t0)))
    for label, name in (("load library", "libload"), ("validate pages", "_tui_validate.gate"),
                        ("load cache", "tui.cache.load_dir"), ("build caches (splash)", "tui.cache.warm_with_spinner"),
                        ("save cache", "tui.cache.dump_dir"), ("init terminal", "tui.init"),
                        ("load first page", "tui.load_cached")):
        e = _first(sess, "E", name)
        if e:
            spans.append((label, ms(e.t0), ms(e.t1)))
    run = _first(sess, "B", "tui.run")
    rend = _first(sess, "E", "tui.render", run.t0 if run else 0.0)
    if rend:
        spans.append(("first frame", ms(rend.t0), ms(rend.t1)))
    return {
        "spans": spans,
        "first_output_ms": ms(sess.first_out) if sess.first_out else None,
        "ready_ms": ms(rend.t1) if rend else None,
        "rss_kb": sess.rss_kb(),
        "cpu_ms": sess.cpu_seconds() * 1000,
    }


def start_app(cfg, home, label, tracer=None):
    fwd = tracer.send if tracer else None
    sess = Session(home, cfg.rows, cfg.cols, trace_w=tracer.w if tracer else None, forward=fwd,
                   probes=tracer is None)
    if fwd:
        fwd(("label", label, int(now() * 1e6), True))
    sess.start()
    if tracer:
        tracer.release_write_end()

    def ready():
        if not sess.alive:
            return True
        if tracer:  # no wrappers while tracing: the app's own `ready` hook marks the main loop
            return _first(sess, "E", "ready") is not None
        run = _first(sess, "B", "tui.run")
        return bool(run and _first(sess, "E", "tui.render", run.t0))

    sess.pump(cfg.start_timeout, until=ready)
    if tracer:  # first frame still to come, traced it takes a few x longer than untraced
        sess.pump(max(1.0, cfg.hints.get(label, 1.0) * 4))
        rd = _first(sess, "E", "ready")
        tl = {"spans": [], "first_output_ms": ((sess.first_out - sess.t_spawn) * 1000) if sess.first_out else None,
              "ready_ms": ((rd.t1 - sess.t_spawn) * 1000) if rd else None, "rss_kb": sess.rss_kb(),
              "cpu_ms": sess.cpu_seconds() * 1000}
    else:
        tl = startup_timeline(sess)
    sess.pump(0.4)  # let the first frames flush before the next scenario
    if fwd:
        fwd(("label_end", int(now() * 1e6)))
    tl["ok"] = tl["ready_ms"] is not None
    return sess, tl


def _died(sess, step, ui, warnings):
    """An app that exits before the final quit is a finding of its own."""
    if sess.alive or step.group == "shutdown":
        return False
    msg = f"app exited during '{step.describe()}' ({sess.exit_info() or 'unknown status'}); later steps were skipped"
    warnings.append(msg)
    ui.warn(msg)
    return True


def _failed(step, res, warnings, ui):
    """A step that could not do what it was asked (text not on screen, landmark missing) is a finding, not a gap."""
    if res.get("ok") is False and res.get("note"):
        msg = f"step '{step.describe()}' failed: {res['note']}"
        if msg not in warnings:
            warnings.append(msg)
            ui.warn(msg)


class _LockedUI:
    """Units that run side by side report to one terminal."""

    def __init__(self, ui):
        self._ui, self._lock = ui, threading.Lock()

    def __getattr__(self, name):
        fn = getattr(self._ui, name)

        def call(*a, **k):
            with self._lock:
                return fn(*a, **k)
        return call


def _copy_home(template):
    """A private HOME with the warmed cache of the template: every unit starts from the same state."""
    home = tempfile.mkdtemp(prefix="dprof-home-")
    shutil.copytree(template, home, symlinks=True, dirs_exist_ok=True)
    return home


def warmed_template(cfg, ui, out, tag):
    """A throw-away HOME with a warmed cache: a cold start fills it, a second start proves it is warm. Both are
    measured (startup.cold / startup.warm) when the run wants them. Returns the HOME."""
    keep = lambda g: cfg.wanted is None or g in cfg.wanted
    home = tempfile.mkdtemp(prefix="dprof-template-")
    for which in ("cold", "warm"):
        name = "startup." + which
        ui.step_begin(f"{name} · {tag}" if keep(name) else f"{name} (setup)")
        sess, tl = start_app(cfg, home, name)
        if keep(name):
            out["startup"][which] = tl
        ui.step_end(name, {"group": name if keep(name) else "setup", "settle_ms": tl["ready_ms"], "tl": tl})
        sess.close()
    return home


def run_unit(cfg, ui, template, unit, sampler=None, jobs=1):
    """One unit, untraced: copy the warmed HOME, start the app (lands on the default page), run the steps."""
    res = {"unit": unit.name, "actions": [], "warnings": [], "setup": []}
    home = _copy_home(template)
    t0 = time.time()
    try:
        ui.step_begin(f"{unit.name} · start")
        sess, tl = start_app(cfg, home, "setup")
        ui.step_end(f"{unit.name} · start", {"group": "setup", "settle_ms": tl["ready_ms"], "tl": tl})
        res["setup"].append({"detail": "start app (warm cache)", "ms": tl["ready_ms"], "ok": tl["ok"]})
        if not tl["ok"]:
            res["warnings"].append(f"unit '{unit.name}': the app did not reach its first frame; its steps were skipped")
            sess.close()
            return res
        t_steps = time.time()
        rss = 0
        for step in unit.steps:
            if not sess.alive:
                break
            ui.step_begin(step.describe())
            r = sess.perform(step)
            rss = max(rss, r.get("rss_kb") or 0)
            if step.group != "setup":
                res["actions"].append(r)
            else:   # getting to the start state is profiled too, but kept out of the measured groups
                res["setup"].append({"detail": step.detail, "ms": r.get("settle_ms"), "busy_ms": r.get("busy_ms"),
                                     "frames": r.get("frames"), "bytes": r.get("bytes"), "ok": r.get("ok") is not False})
            ui.step_end(step.describe(), r)
            _failed(step, r, res["warnings"], ui)
            if _died(sess, step, ui, res["warnings"]):
                break
        cpu_s = sess.cpu_seconds()
        t1 = time.time()
        sess.close()
    finally:
        shutil.rmtree(home, ignore_errors=True)
    if sampler:
        res["resources"] = dict(sampler.summary(t_steps, t1, cpu_s, rss), unit=unit.name, jobs=jobs)
    return res


def latency_round(cfg, ui, round_no, sampler=None):
    """One untraced pass: cold start and warm start build the template, then every unit runs from a copy of it,
    `cfg.jobs` at a time."""
    out = {"startup": {}, "actions": [], "warnings": [], "resources": [], "setup": []}
    template = None
    try:
        template = warmed_template(cfg, ui, out, f"round {round_no + 1}/{cfg.rounds}")
        todo = units(cfg.rows, cfg.cols, cfg.quick, cfg.wanted)
        jobs = max(1, min(cfg.jobs, len(todo))) if todo else 1
        if jobs > 1:
            out["warnings"].append(f"{jobs} units ran side by side: timings include the contention between them")
            shared = _LockedUI(ui)
            with ThreadPoolExecutor(max_workers=jobs) as pool:
                results = list(pool.map(lambda u: run_unit(cfg, shared, template, u, sampler, jobs), todo))
        else:
            results = [run_unit(cfg, ui, template, u, sampler, 1) for u in todo]
        for r in results:
            out["actions"] += r["actions"]
            out["warnings"] += r["warnings"]
            out["setup"].append({"unit": r["unit"], "steps": r["setup"]})
            if "resources" in r:
                out["resources"].append(r["resources"])
    finally:
        if template:
            shutil.rmtree(template, ignore_errors=True)
    return out


def traced_session(cfg, ui, cold):
    """Traced passes (always one at a time: xtrace is heavy and a shared machine would blur it).
    cold=True: only the cold start. Otherwise the warm start, then every unit from a copy of the warmed HOME."""
    results = []
    template = tempfile.mkdtemp(prefix="dprof-template-")
    try:
        if cold:
            results.append(_traced(cfg, ui, template, "startup.cold", []))
            return results
        s0, _ = start_app(cfg, template, "warmup")   # untraced: fills the cache
        s0.close()
        results.append(_traced(cfg, ui, template, "startup.warm", []))
        for unit in units(cfg.rows, cfg.cols, cfg.quick, cfg.wanted):
            results.append(_traced(cfg, ui, template, unit.name, unit.steps))
        return results
    finally:
        shutil.rmtree(template, ignore_errors=True)


def _traced(cfg, ui, template, name, steps):
    tracer = Tracer(WRAPPED)
    ui.set_tracer(tracer)
    home = template if name == "startup.cold" else _copy_home(template)
    actions, warnings = [], []
    try:
        label = name if name.startswith("startup.") else "setup"
        ui.step_begin(f"{name} (traced)")
        sess, tl = start_app(cfg, home, label, tracer)
        ui.step_end(name, {"group": label, "settle_ms": tl["ready_ms"], "tl": tl, "traced": True})
        if name == "startup.cold" or not steps:
            sess.close()
        else:
            for step in steps:
                if not sess.alive:
                    break
                step.wait = min(8.0, cfg.hints.get(step.group, 0.3) * 3 + 0.3)
                ui.step_begin(step.describe())
                res = sess.perform(step)
                actions.append(res)
                ui.step_end(step.describe(), res)
                _failed(step, res, warnings, ui)
                if _died(sess, step, ui, warnings):
                    break
            sess.close()
        ui.note("closing trace, folding results")
        data = tracer.finish()
    finally:
        if home != template:
            shutil.rmtree(home, ignore_errors=True)
    return {"trace": data, "startup": tl, "actions": actions, "warnings": warnings}
