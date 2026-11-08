"""Scenario API. A scenario is a plain function that drives an app through a Ctx:

    @scenario("my-scenario", ready="Welcome", title="What it measures")
    def my_scenario(c):
        c.step("nav.settings", click(5, 3), expect="Settings")     # input -> time until the screen shows the text
        c.step("scroll.burst", DOWN * 10, expect="Item 10")
        c.step("type.word", chars("hello"), gap_ms=30, expect="hello")
        c.step("resize.small", resize=(30, 90))
        c.idle("idle.2s", 2)
        c.memory("memory")

Steps with the same name are samples of one measurement (call c.step in a loop to collect many per round).
`ready` (str | Expect | {app_name: ...}) says when the app has finished starting."""
import time
from dataclasses import dataclass, field
from typing import Callable

from .expect import as_expect

SCENARIOS = {}


@dataclass
class Scenario:
    name: str
    fn: Callable
    ready: object
    title: str = ""
    rows: int = 45
    cols: int = 150
    apps: tuple = ()  # app names it can run (empty = any)
    default_apps: tuple = ()  # app names `run SCENARIO` uses when --apps is not given; the first is the baseline


def scenario(name, ready, title="", rows=45, cols=150, apps=(), default_apps=()):
    def deco(fn):
        SCENARIOS[name] = Scenario(name, fn, ready, title or (fn.__doc__ or "").strip().split("\n")[0], rows, cols, tuple(apps),
                                  tuple(default_apps) or tuple(apps))
        return fn
    return deco


class Ctx:
    """What a scenario function sees. Collects one result dict per call."""

    def __init__(self, run, app, results, snapshots, report=None, rnd=0):
        self.run, self.app, self._results, self._snaps, self._rep = run, app, results, snapshots, report
        self._rnd = rnd

    def _record(self, name, fn):
        """Runs one measurement, tells the reporter before and after, stores the result."""
        if self._rep:
            self._rep.step_begin(name)
        r = fn()
        self._results.append(r)
        if self._rep:
            self._rep.step_end(self.app.name, self._rnd, r)
        return r

    @property
    def rows(self):
        return self.run.rows

    @property
    def cols(self):
        return self.run.cols

    def step(self, name, send=None, expect=None, *, resize=None, gap_ms=0, timeout=8.0, quiet=None, snap=False):
        """Send input (bytes, or a list of bytes written `gap_ms` apart) and/or resize, then time until `expect` shows.
        Without `expect` the step measures until the screen stops changing."""
        parts = [send] if isinstance(send, (bytes, bytearray)) else list(send or [])

        def action(run):
            if resize:
                run.resize(*resize)
            for i, p in enumerate(parts):
                if i and gap_ms:
                    time.sleep(gap_ms / 1000)
                run.sess.send(p)

        r = self._record(name, lambda: self.run.step(name, action, as_expect(expect), timeout, quiet))
        if snap:
            self._snaps[name] = self.run.snapshot()
        return r

    def idle(self, name, seconds=2.0):
        self._record(name, lambda: self.run.idle(name, seconds))

    def memory(self, name="memory"):
        self._record(name, lambda: self.run.memory(name))

    def pause(self, seconds):
        """Untimed sleep."""
        time.sleep(seconds)

    def wait_for(self, expect, timeout=30.0):
        """Untimed wait for the screen to show something."""
        return self.run.wait_for(expect, timeout)

    def snapshot(self, label):
        """Saves the current screen text into the report (to show both apps did the same work)."""
        self._snaps[label] = self.run.snapshot()
