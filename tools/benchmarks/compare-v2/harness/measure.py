"""One app under test: runs steps against it and turns the recorded byte stream into measurements.

Definitions (all in ms from the moment the input was written, or from spawn for startup):
  first_byte   first output byte of any kind
  first_paint  first chunk after which the visible screen differs from before
  ready        first chunk after which the step's Expect is true on the emulated screen (= settled if the step has none)
  settled      last chunk that changed the visible screen ('visually complete'); trailing no-op bytes do not count
Steps with several inputs (typing with gaps) are timed from their LAST input, so the gaps you chose are not counted as latency;
CPU, bytes, writes and paints cover the whole step.
  paints       number of visible screen changes (1 = one clean frame; many = progressive or redundant repainting)
A step ends once output has been quiet for `quiet` seconds and the Expect holds (or the timeout hits). The quiet window only
decides when to stop watching; it is never part of a reported time."""
import time

from .expect import View, as_expect
from .probe import Probe
from .term import Emulator, Session

MS = 1e6
POLL = 0.002


class Run:
    def __init__(self, argv, env, cwd, rows, cols, cpus=None, quiet=0.15, replies=True, keyboard="auto"):
        self.rows, self.cols, self.quiet = rows, cols, quiet
        self.emu = Emulator(rows, cols)
        self.view = View(self.emu.screen)
        self.sess = Session(argv, env, cwd, rows, cols, cpus, replies, keyboard)
        self.probe = Probe(self.sess.pid)
        self._pos = 0  # events already replayed into the emulator
        self.max_timeout = None  # --step-timeout: caps every step's own timeout

    # ---- replay -------------------------------------------------------------------------------------------------
    def _replay(self, expect=None, frames=None):
        """Feeds unreplayed chunks to the emulator. Returns t of the first chunk after which `expect` held (or None)."""
        ev, hit = self.sess.events, None
        while self._pos < len(ev):
            t, data = ev[self._pos]
            self._pos += 1
            if self.emu.feed(data):
                self.view.invalidate()
                if frames is not None:
                    frames.append(t)
                if hit is None and expect is not None and expect(self.view):
                    hit = t
        return hit

    def _last_t(self, i0):
        ev = self.sess.events
        return ev[-1][0] if len(ev) > i0 else None

    def drain(self, limit=3.0):
        """Waits for the app to go quiet and brings the emulator up to date (untimed)."""
        end = time.perf_counter() + limit
        while time.perf_counter() < end:
            last = self._last_t(0)
            if last is None or time.perf_counter_ns() - last >= self.quiet * 1e9:
                break
            time.sleep(POLL)
        self._replay()
        self.view.invalidate()

    def wait_for(self, expect, timeout=30.0):
        """Untimed wait until `expect` has been true on some visible frame (a transient message counts)."""
        expect, end = as_expect(expect), time.perf_counter() + timeout
        if expect(self.view):
            return True
        while time.perf_counter() < end and not self.sess.eof:
            if self._replay(expect) is not None:
                return True
            time.sleep(POLL)
        return False

    # ---- measurements -------------------------------------------------------------------------------------------
    def _observe(self, name, t_first, i_first, cpu0, expect, timeout, quiet, stale=False, t0=None):
        """Watches the output after an input until it is quiet (and `expect` holds). t_first/i_first = first input, t0 = last input."""
        sess, frames, hit = self.sess, [], None
        t0 = t0 or t_first
        deadline, q = t0 + timeout * 1e9, quiet * 1e9
        while True:
            time.sleep(POLL)
            now = time.perf_counter_ns()
            n = len(sess.events)
            last = sess.events[-1][0] if n > i_first else None
            still = (last is None and now - t0 < 2 * q) or (last is not None and now - last < q)
            if sess.eof or now > deadline or not still:
                h = self._replay(expect, frames)
                hit = hit or h
                if len(sess.events) > n:
                    continue
                if sess.eof or now > deadline or expect is None or hit is not None:
                    break
        ev = sess.events[i_first:self._pos]
        cpu1 = self.probe.cpu_ns() if not sess.eof else cpu0
        ok = expect is None or hit is not None
        ms = lambda t: None if t is None else max(0.0, (t - t0) / MS)
        after = [t for t in frames if t >= t0]
        late = [t for t, _ in ev if t >= t0]
        settled = ms(after[-1]) if after else None
        return {"name": name, "kind": "latency", "ok": ok, "stale": stale, "expect": None if expect is None else str(expect),
                "first_byte_ms": ms(late[0]) if late else None, "first_paint_ms": ms(after[0]) if after else None,
                "ready_ms": ms(hit) if expect is not None else settled, "settled_ms": settled,
                "paints": len(frames), "writes": len(ev), "bytes": sum(len(d) for _, d in ev),
                "cpu_ms": (cpu1 - cpu0) / MS, **({} if ok else {"screen": self.view.text})}

    def startup(self, expect, timeout=30.0):
        """Spawn -> ready, measured from just before fork."""
        expect = as_expect(expect)
        return self._observe("startup", self.sess.t_spawn, 0, 0, expect, timeout, self.quiet)

    def step(self, name, action, expect=None, timeout=8.0, quiet=None):
        """Runs action(run) and times its effect. `action` writes input and/or resizes."""
        expect = as_expect(expect)
        timeout = min(timeout, self.max_timeout) if self.max_timeout else timeout
        self.drain()
        stale = expect is not None and expect(self.view)  # already true before the input: the step would measure nothing
        i0, cpu0 = len(self.sess.events), self.probe.cpu_ns()
        t_first = time.perf_counter_ns()
        action(self)
        t_last = self.sess.last_send[0]
        return self._observe(name, t_first, i0, cpu0, expect, timeout, quiet or self.quiet, stale, t_last if t_last >= t_first else None)

    def idle(self, name, seconds):
        """Sits still and records what the app does on its own: CPU, wakeups, bytes."""
        self.drain()
        i0, cpu0, t0 = len(self.sess.events), self.probe.cpu_ns(), time.perf_counter_ns()
        time.sleep(seconds)
        cpu1, t1 = self.probe.cpu_ns(), time.perf_counter_ns()
        ev = [e for e in self.sess.events[i0:] if e[0] <= t1]
        dt = (t1 - t0) / 1e9
        return {"name": name, "kind": "idle", "ok": True, "cpu_pct": (cpu1 - cpu0) / (dt * 1e9) * 100,
                "wakeups_s": len(ev) / dt, "bytes_s": sum(len(d) for _, d in ev) / dt}

    def memory(self, name):
        self.drain()
        return {"name": name, "kind": "memory", "ok": True, **self.probe.mem()}

    def resize(self, rows, cols):
        """Resizes the pty (SIGWINCH to the app) and the emulated screen together."""
        self.emu.resize(rows, cols)
        self.sess.set_size(rows, cols)
        self.rows, self.cols = rows, cols

    def snapshot(self):
        self.drain()
        return self.view.text

    def total_cpu_ms(self):
        return self.probe.cpu_ns() / MS

    def close(self):
        self.sess.close()
