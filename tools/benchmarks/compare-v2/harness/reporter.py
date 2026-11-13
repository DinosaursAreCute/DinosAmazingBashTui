"""Reporters: how a run shows what it is doing. The runner only calls the hooks below; which reporter listens is a CLI choice,
and several can listen at once (Multi). A reporter knows nothing about pty, emulator or statistics, so it can serve any
runner that emits the same hooks.

Hooks (all optional, all no-ops in the base class):
  run_start(meta)                  meta: scenario, title, apps [{name,label,color}], rounds, warmup
  round_start(app, rnd, total)     rnd < 0 = warm-up; total = measured rounds
  step_begin(name)                 a step of the current round starts
  step_end(app, rnd, result)       it finished; result is the measured dict (ready_ms, cpu_ms, ...)
  round_end(app, seconds, error)   error is a one-line message or None
  warn(text)
  run_end(res, analysis)           after statistics: the final report
"""
import json
import time

from rich.console import Console
from rich.live import Live
from rich.text import Text

from .stats import METRICS

SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"


class Reporter:
    def run_start(self, meta): pass
    def round_start(self, app, rnd, total): pass
    def step_begin(self, name): pass
    def step_end(self, app, rnd, result): pass
    def round_end(self, app, seconds, error=None): pass
    def warn(self, text): pass
    def run_end(self, res, analysis): pass


class Multi(Reporter):
    def __init__(self, *reporters):
        self.rs = reporters

    def __getattribute__(self, name):
        if name in Reporter.__dict__ and not name.startswith("_"):
            rs = object.__getattribute__(self, "rs")
            return lambda *a, **k: [getattr(r, name)(*a, **k) for r in rs] and None
        return object.__getattribute__(self, name)


class JsonReporter(Reporter):
    """One JSON object per line (machine-readable progress for other tools)."""

    def __init__(self, path):
        self.f = open(path, "a", buffering=1)
        self.app = self.rnd = None

    def _w(self, kind, **kw):
        self.f.write(json.dumps({"t": time.time(), "event": kind, **kw}) + "\n")

    def run_start(self, meta): self._w("run_start", scenario=meta["scenario"], apps=[a["name"] for a in meta["apps"]], rounds=meta["rounds"], warmup=meta["warmup"])
    def round_start(self, app, rnd, total): self.app, self.rnd = app, rnd; self._w("round_start", app=app, round=rnd)
    def step_begin(self, name): self._w("step_begin", app=self.app, round=self.rnd, step=name)
    def step_end(self, app, rnd, result): self._w("step_end", app=app, round=rnd, result=result)
    def round_end(self, app, seconds, error=None): self._w("round_end", app=app, seconds=round(seconds, 2), error=error)
    def warn(self, text): self._w("warn", text=text)
    def run_end(self, res, analysis): self._w("run_end"); self.f.close()


def mmss(sec):
    sec = max(0, sec)
    return f"{int(sec // 60):02d}:{sec % 60:04.1f}"


def short(sec):
    sec = int(max(0, sec))
    return f"{sec // 60}:{sec % 60:02d}"


def fmt(v, key):
    from .report_term import num
    return num(v, key)


class ConsoleReporter(Reporter):
    """Scrolling log of finished steps with their measured values (and the median so far for that step), under a footer that
    shows the running step, progress and ETA. live=False prints the log lines only (no footer), for pipes and CI."""

    def __init__(self, live=True, stream=None):
        self.con = Console(file=stream, stderr=stream is None)
        self.live = live and self.con.is_terminal
        self.meta = None
        self.app = self.tag = ""
        self.cur = None  # (step name, t0)
        self.steps_done = self.steps_per_round = 0
        self.rounds_done = self.rounds_total = 0
        self.t_start = time.time()
        self.seen = {}  # (app, step) -> ready values of earlier rounds
        self.colors = {}
        self._live = None

    # ---- hooks --------------------------------------------------------------------------------------------------
    def run_start(self, meta):
        self.meta = meta
        self.colors = {a["name"]: a["color"] for a in meta["apps"]}
        self.rounds_total = len(meta["apps"]) * (meta["rounds"] + meta["warmup"])
        self.t_start = time.time()
        self.con.print(Text.assemble(("compare-v2 ", "bold blue"), (f"{meta['scenario']}", "bold"), (f"  {meta['title']}", "dim")))
        self.con.print(Text(f"  {len(meta['apps'])} apps × ({meta['rounds']} rounds + {meta['warmup']} warm-up)  ·  {meta['cols']}x{meta['rows']}", style="dim"))
        if self.live:
            self._live = Live(get_renderable=self._footer, console=self.con, refresh_per_second=10, transient=True)
            self._live.start()

    def round_start(self, app, rnd, total):
        self.app = app
        self.tag = "warm-up" if rnd < 0 else f"r{rnd + 1}/{total}"
        self.steps_done = 0
        self.cur = ("starting", time.time())

    def step_begin(self, name):
        self.cur = (name, time.time())

    def step_end(self, app, rnd, r):
        self.steps_done += 1
        self.cur = ("between steps", time.time())
        self.con.print(self._line(app, rnd, r))
        if rnd >= 0 and r.get("ok") and r["kind"] == "latency" and r.get("settled_ms") is not None:
            self.seen.setdefault((app, r["name"]), []).append(r["settled_ms"])

    def round_end(self, app, seconds, error=None):
        self.rounds_done += 1
        self.steps_per_round = max(self.steps_per_round, self.steps_done)
        if error:
            self.con.print(Text(f"  ✗ {app} {self.tag} failed: {error}", style="red"))
        else:
            self.con.print(Text(f"  ── {app} {self.tag} done in {seconds:.1f}s", style="dim"))

    def warn(self, text):
        self.con.print(Text("⚠ " + text, style="yellow"))

    def run_end(self, res, analysis):
        if self._live:
            self._live.stop()
            self._live = None
        from .report_term import render
        render(res, analysis, file=None)

    # ---- drawing ------------------------------------------------------------------------------------------------
    def _line(self, app, rnd, r):
        t = Text()
        ok = r.get("ok", True)
        t.append(" ✓ " if ok else " ✗ ", style="green" if ok else "bold red")
        t.append(mmss(time.time() - self.t_start) + "  ", style="dim")
        t.append(f"{app:<9}", style=self.colors.get(app, "white"))
        t.append(f"{self.tag:<8}", style="dim")
        t.append(f"{r['name']:<19}", style="bold")
        if not ok:
            t.append(f"expected {r['expect']!s} never appeared" if r.get("expect") else "failed", style="red")
            return t
        if r["kind"] == "latency":
            t.append("done ", style="dim")
            t.append(f"{fmt(r['settled_ms'], 'settled_ms')} ms", style="bold cyan")
            t.append(f" (ready {fmt(r['ready_ms'], 'ready_ms')})", style="dim")
            prev = self.seen.get((app, r["name"]))
            if prev and rnd >= 0:
                import statistics
                t.append(f" (med {statistics.median(prev):.1f} n={len(prev)})", style="dim")
            t.append(f" · cpu {fmt(r['cpu_ms'], 'cpu_ms')} ms · {fmt(r['bytes'], 'bytes')} · {r['paints']} paint{'s' * (r['paints'] != 1)}", style="dim")
            if r.get("stale"):
                t.append("  stale: expectation was already true", style="yellow")
        elif r["kind"] == "idle":
            t.append(f"cpu {r['cpu_pct']:.2f}% · {r['wakeups_s']:.1f} wakeups/s · {fmt(r['bytes_s'], 'bytes_s')}", style="cyan")
        else:
            t.append(f"PSS {fmt(r['pss_kb'], 'pss_kb')} · RSS {fmt(r['rss_kb'], 'rss_kb')} · {r['procs']} proc · {r['threads']} thr", style="cyan")
        return t

    def _footer(self):
        now = time.time()
        spin = SPIN[int(now * 10) % len(SPIN)]
        name, t0 = self.cur or ("", now)
        n = f"/{self.steps_per_round}" if self.steps_per_round else ""
        l1 = Text.assemble((f" {spin} ", "bold cyan"), (self.app, self.colors.get(self.app, "white")), (f"  {self.tag}  ", "dim"),
                           (name, "bold"), (f"  {now - t0:4.1f}s", "yellow"), (f"   step {self.steps_done + 1}{n}", "dim"))
        frac = (self.rounds_done + (min(1, self.steps_done / self.steps_per_round) if self.steps_per_round else 0)) / max(1, self.rounds_total)
        el = now - self.t_start
        w = 30
        fill = int(frac * w)
        l2 = Text.assemble(("   ", ""), ("█" * fill, "cyan"), ("░" * (w - fill), "dim"), (f" {frac * 100:3.0f}%", "bold"),
                           (f"  round {min(self.rounds_done + 1, self.rounds_total)}/{self.rounds_total}  elapsed {short(el)}", "dim"),
                           (f"  ETA {short(el / frac - el)}" if frac > 0.03 else "", "dim"))
        return Text("\n").join([l1, l2])


def make(kind, events=None):
    """kind: live | plain | none; events: path for an extra JSON-lines reporter."""
    base = {"live": lambda: ConsoleReporter(True), "plain": lambda: ConsoleReporter(False), "none": Reporter}[kind]()
    return Multi(base, JsonReporter(events)) if events else base
