"""Orchestrates profiler runs: latency rounds (untraced) and attribution runs (traced)."""
import os
import shutil
import tempfile
import time

from .scenarios import interaction_steps
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


def latency_round(cfg, ui, round_no):
    """One untraced pass: cold start, warm start, then the selected steps."""
    home = tempfile.mkdtemp(prefix="dprof-home-")
    out = {"startup": {}, "actions": [], "warnings": []}
    keep = lambda g: cfg.wanted is None or g in cfg.wanted   # unwanted starts still run: they prepare the cache
    try:
        tag = f"round {round_no + 1}/{cfg.rounds}"
        for which in ("cold", "warm"):
            name = "startup." + which
            ui.step_begin(f"{name} · {tag}" if keep(name) else f"{name} (setup)")
            sess, tl = start_app(cfg, home, name)
            if keep(name):
                out["startup"][which] = tl
            ui.step_end(name, {"group": name if keep(name) else "setup", "settle_ms": tl["ready_ms"], "tl": tl})
            if which == "cold":
                sess.close()
        for step in interaction_steps(cfg.rows, cfg.cols, cfg.quick, cfg.wanted):
            if not sess.alive:
                break
            ui.step_begin(step.describe())
            res = sess.perform(step)
            if step.group != "setup":
                out["actions"].append(res)
            ui.step_end(step.describe(), res)
            if _died(sess, step, ui, out["warnings"]):
                break
        sess.close()
    finally:
        shutil.rmtree(home, ignore_errors=True)
    return out


def traced_session(cfg, ui, cold):
    """One traced pass. cold=True: only the cold start. Otherwise warm start + the script."""
    tracer = Tracer(WRAPPED)
    ui.set_tracer(tracer)
    home = tempfile.mkdtemp(prefix="dprof-home-")
    actions, warnings = [], []
    try:
        if not cold:  # warm the on-disk cache first, untraced
            s0, _ = start_app(cfg, home, "warmup")
            s0.close()
        name = "startup.cold" if cold else "startup.warm"
        ui.step_begin(name + " (traced)")
        sess, tl = start_app(cfg, home, name, tracer)
        ui.step_end(name, {"group": name, "settle_ms": tl["ready_ms"], "tl": tl, "traced": True})
        if cold:
            sess.close()
        else:
            for step in interaction_steps(cfg.rows, cfg.cols, cfg.quick, cfg.wanted):
                if not sess.alive:
                    break
                step.wait = min(8.0, cfg.hints.get(step.group, 0.3) * 3 + 0.3)
                ui.step_begin(step.describe())
                res = sess.perform(step)
                actions.append(res)
                ui.step_end(step.describe(), res)
                if _died(sess, step, ui, warnings):
                    break
            sess.close()
        ui.note("closing trace, folding results")
        data = tracer.finish()
    finally:
        shutil.rmtree(home, ignore_errors=True)
    return {"trace": data, "startup": tl, "actions": actions, "warnings": warnings}
