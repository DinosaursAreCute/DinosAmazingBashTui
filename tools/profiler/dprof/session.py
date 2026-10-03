"""One live run of a DABT app inside a pseudo-terminal.

The session is the profiler's "user": it types, moves the mouse, resizes the window and
measures how the app answers. Latency comes from probe events the app writes on fd 8
(see probe_shim.sh), not from watching the screen: the app repaints its footer ~20x/s
when idle, so "output went quiet" is not a usable settle signal.
"""
import fcntl
import os
import pty
import select
import signal
import struct
import tempfile
import re
import termios
import time
import shutil

CLK_TCK = os.sysconf("SC_CLK_TCK")
HERE = os.path.dirname(os.path.abspath(__file__))
PROFILER_DIR = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(PROFILER_DIR))

# name:kind - w/p/a = user-visible work (nesting depth), s = span only, f = one flushed frame
WRAP = [
    ("_tui_input.key_event", "w"), ("_tui._handle_mouse", "w"), ("_tui._flush_pending_render", "p"),
    ("_tui._apply_resize", "w"), ("_tui_overlay.draw_all", "a"), ("tui.render", "w"),
    ("tui.goto", "w"), ("tui.hook.fire", "w"), ("_master_cleanup", "w"),
    ("_tui._flush", "f"),
    ("_tui_validate.gate", "w"), ("tui.cache.load_dir", "w"), ("tui.cache.warm_with_spinner", "w"),
    ("tui.cache.dump_dir", "w"), ("tui.init", "w"), ("tui.load_cached", "w"),
    ("_tui_validate.notify", "w"), ("tui.run", "s"),
    ("tui.cache.replay", "s"), ("_tui_cache_run_on_visit", "s"), ("_tui._draw_pane_buf", "n"),
    # tui.page.refresh (lib/markup/tui_refresh.sh) and background jobs (lib/tui_job.sh). _tui_job.tick runs on every loop
    # pass while a job is pending and is deliberately not probed. _tui_job.finish is a span only: a job lands when it is
    # done, not as part of the click that started it, so it must not stretch that click's settle time.
    ("tui.page.refresh", "w"), ("tui.job.run", "w"), ("_tui_job.finish", "s"), ("_tui_job.spinner_draw", "s"),
]
WORK_FNS = {n for n, k in WRAP if k in "wpa"}
WRAPPED = {n for n, _ in WRAP}
_TOKEN = re.compile(r"\x1b\[(\d+);(\d*)H|\x1b(?:\[[0-9;?<>=]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|[78=>])|([^\x1b\r\n]+)")
XTVERSION_REPLY = b"\x1bP>|xterm(388)\x1b\\"


ACTIVE = []   # live sessions, so an abort can kill every app we started


def kill_all():
    for s in list(ACTIVE):
        try:
            os.kill(s.pid, signal.SIGKILL)
        except (OSError, TypeError):
            pass


def now():
    return time.time()


def _click(x, y):
    return b"\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (x, y, x, y)


def us_to_s(us):
    return us / 1e6


class Event:
    __slots__ = ("kind", "name", "t0", "t1", "arg", "chain")

    def __init__(self, kind, name, t0, t1=0.0, arg=0, chain=""):
        self.kind, self.name, self.t0, self.t1, self.arg, self.chain = kind, name, t0, t1, arg, chain


def _pane_costs(evs):
    """{pane id: [draws, wall ms]} for the _tui._draw_pane_buf spans inside one action."""
    out = {}
    for e in evs:
        if e.kind == "E" and e.name == "_tui._draw_pane_buf" and e.chain:
            o = out.setdefault(e.chain, [0, 0.0])
            o[0] += 1
            o[1] += (e.t1 - e.t0) * 1000
    return out


class Session:
    def __init__(self, home, rows=45, cols=150, trace_w=None, app=None, forward=None, probes=True):
        """home: throw-away HOME dir. trace_w: write end of the xtrace pipe (or None).
        forward: callable(msg) receiving driver->aggregator messages (or None)."""
        self.home, self.rows, self.cols = home, rows, cols
        self.probes = probes      # False while tracing: wrappers would hide the real file:line of what they wrap
        self.raw = bytearray()    # tail of the terminal output, for locate()
        self.trace_w = trace_w
        self.app = app or os.path.join(REPO, "bin", "DABT_demo.sh")
        self.forward = forward
        self.events = []          # every probe event, in arrival order
        self.open_work = 0        # currently open work wrappers
        self.last_work_end = 0.0
        self.out_bytes = 0
        self.last_out = 0.0
        self.out_times = []   # arrival time of every pty read: the ground truth for "painted", direct draws included
        self.first_out = 0.0
        self.main_pid = None
        self.alive = False
        self.pid = None
        self.t_spawn = 0.0
        self._pbuf = b""
        self._hb_at = 0.0
        self._tmp = tempfile.mkdtemp(prefix="dprof-app-")

    # ── lifecycle ────────────────────────────────────────────────────────────
    def _write_app_copy(self):
        """Copy of the app script that sources the probe shim instead of lib/tui.sh, with
        $(dirname "$0") pinned to the real bin dir so every relative path still resolves."""
        with open(self.app) as f:
            text = f.read()
        bindir = os.path.dirname(os.path.abspath(self.app))
        shim = os.path.join(PROFILER_DIR, "probe_shim.sh")
        text = text.replace('"$(dirname "$0")/../lib/tui.sh"', f'"{shim}"')
        text = text.replace('$(dirname "$0")', bindir)
        path = os.path.join(self._tmp, "app.sh")
        with open(path, "w") as f:
            f.write(text)
        return path

    def start(self):
        probe_r, probe_w = os.pipe()
        self.probe_r = probe_r
        app_copy = self._write_app_copy()
        wrap = " ".join(f"{n}:{k}" for n, k in WRAP) if self.probes else ""
        env = dict(os.environ)
        env.update(
            HOME=self.home, XDG_CONFIG_HOME=self.home + "/.config", XDG_CACHE_HOME=self.home + "/.cache",
            XDG_DATA_HOME=self.home + "/.local/share", XDG_STATE_HOME=self.home + "/.local/state",
            TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8", LANG="C.UTF-8", TZ="UTC",
            PROF_REPO=REPO, PROF_WRAP=wrap, PROF_TRACE="1" if self.trace_w is not None else "0",
        )
        self.t_spawn = now()
        pid, fd = pty.fork()
        if pid == 0:
            try:
                os.dup2(probe_w, 8)
                if self.trace_w is not None:
                    os.dup2(self.trace_w, 9)
                for f in range(10, 256):
                    try:
                        os.close(f)
                    except OSError:
                        pass
                os.chdir(REPO)
                os.execvpe("bash", ["bash", app_copy], env)
            finally:
                os._exit(127)
        os.close(probe_w)
        self.pid, self.pty = pid, fd
        ACTIVE.append(self)
        self.alive = True
        self.resize(self.rows, self.cols, signal_app=False)
        return self

    def resize(self, rows, cols, signal_app=True):
        self.rows, self.cols = rows, cols
        fcntl.ioctl(self.pty, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        if signal_app and self.alive:
            os.kill(self.pid, signal.SIGWINCH)

    def send(self, data):
        try:
            os.write(self.pty, data)
        except OSError:
            self.alive = False

    def exit_info(self):
        """Human-readable exit status once the app is gone, else None."""
        try:
            pid, st = os.waitpid(self.pid, os.WNOHANG)
        except (OSError, ChildProcessError):
            return getattr(self, "_exit", None)
        if pid:
            self._exit = (f"exit {os.WEXITSTATUS(st)}" if os.WIFEXITED(st) else f"signal {os.WTERMSIG(st)}")
        return getattr(self, "_exit", None)

    def close(self):
        if self.alive:
            try:
                os.kill(self.pid, signal.SIGTERM)
            except OSError:
                pass
            self.pump(0.3, until=lambda: not self.alive)
        for fd in (getattr(self, "pty", None), getattr(self, "probe_r", None)):
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass
        try:
            os.waitpid(self.pid, os.WNOHANG)
        except (OSError, ChildProcessError):
            pass
        if self in ACTIVE:
            ACTIVE.remove(self)
        shutil.rmtree(self._tmp, ignore_errors=True)

    # ── event pump ───────────────────────────────────────────────────────────
    def pump(self, seconds, until=None, tick=0.004):
        """Reads the pty and probe pipe for up to `seconds`, or until `until()` is true."""
        end = now() + seconds
        while True:
            if until is not None and until():
                return True
            t = now()
            if t >= end:
                return False
            try:
                r, _, _ = select.select([self.pty, self.probe_r], [], [], min(tick, end - t))
            except (OSError, ValueError):
                self.alive = False
                return False
            for fd in r:
                if fd == self.pty:
                    self._read_pty()
                else:
                    self._read_probe()
            self._heartbeat(t)
            if not self.alive:
                self._read_probe()
                return until() if until else False

    def _heartbeat(self, t):
        if self.forward and t - self._hb_at > 0.02:
            self._hb_at = t
            self.forward(("hb", t - 0.06))

    def _read_pty(self):
        try:
            d = os.read(self.pty, 65536)
        except OSError:
            self.alive = False
            return
        if not d:
            self.alive = False
            return
        if not self.out_bytes:
            self.first_out = now()
        self.raw += d
        if len(self.raw) > 400000:
            del self.raw[:-200000]
        self.out_bytes += len(d)
        self.last_out = now()
        self.out_times.append(self.last_out)
        if b"\x1b[>0q" in d:
            self.send(XTVERSION_REPLY)

    def _read_probe(self):
        try:
            d = os.read(self.probe_r, 65536)
        except OSError:
            return
        if not d:
            return
        self._pbuf += d
        *lines, self._pbuf = self._pbuf.split(b"\n")
        for ln in lines:
            self._on_probe(ln.decode("ascii", "replace"))

    def _is_main(self, pid):
        return self.main_pid is None or pid == self.main_pid

    def _on_probe(self, ln):
        p = ln.split("|")
        try:
            if p[0] == "B":
                ev = Event("B", p[1], us_to_s(int(p[2])))
                main = self._is_main(p[3])
                if main and p[1] in WORK_FNS:
                    self.open_work += 1
            elif p[0] == "E":
                t0, t1 = int(p[2]), int(p[3])
                ev = Event("E", p[1], us_to_s(t0), us_to_s(t1), int(p[4]) if p[4].lstrip("-").isdigit() else 0)
                if len(p) > 6:
                    ev.chain = p[6]   # _tui._flush: callers, innermost first, joined by '<'; n-kind spans: first argument
                if p[1] == "shim_start" and self.main_pid is None:
                    self.main_pid = p[5]
                main = self._is_main(p[5])
                if main and p[1] in WORK_FNS:
                    self.open_work = max(0, self.open_work - 1)
                    self.last_work_end = max(self.last_work_end, ev.t1)
                if not main:
                    return
            else:
                return
        except (IndexError, ValueError):
            return
        self.events.append(ev)

    def locate(self, text):
        """(col, row) of the last on-screen occurrence of `text`, read from the cursor-addressed output.
        A word edge of the needle must also be a word edge on screen: 'default' is not found in 'defaults'."""
        found, row, col = None, 1, 1
        needle = text
        edge = lambda c: c.isalnum() or c == "_"
        for m in _TOKEN.finditer(self.raw.decode("utf-8", "replace")):
            cup, chunk = m.group(1), m.group(3)
            if cup is not None:
                row, col = int(cup), int(m.group(2) or 1)
            elif chunk:
                i = chunk.find(needle)
                while i >= 0:
                    j = i + len(needle)
                    if not ((edge(needle[0]) and i and edge(chunk[i - 1])) or (edge(needle[-1]) and j < len(chunk) and edge(chunk[j]))):
                        found = (col + i, row)
                    i = chunk.find(needle, i + 1)
                col += len(chunk)
        return found

    # ── measurements ─────────────────────────────────────────────────────────
    def cpu_seconds(self):
        """utime+stime of the app and every child it has reaped, in seconds."""
        try:
            with open(f"/proc/{self.pid}/stat") as f:
                rest = f.read().rsplit(")", 1)[1].split()
            return sum(int(rest[i]) for i in (11, 12, 13, 14)) / CLK_TCK
        except (OSError, IndexError, ValueError):
            return 0.0

    def rss_kb(self):
        try:
            with open(f"/proc/{self.pid}/status") as f:
                for ln in f:
                    if ln.startswith("VmRSS:"):
                        return int(ln.split()[1])
        except OSError:
            pass
        return 0

    def measure_since(self, mark, t_send):
        """Latency facts for the events that arrived after index `mark`."""
        evs = self.events[mark:]
        works = [e for e in evs if e.kind == "E" and e.name in WORK_FNS]
        flushes = [e for e in evs if e.kind == "E" and e.name == "_tui._flush"]
        if not works:
            return None
        works.sort(key=lambda e: e.t0)
        first = works[0]
        # union of work intervals = time the app was busy on behalf of this action
        busy, cur_s, cur_e = 0.0, None, None
        for w in works:
            if cur_e is None or w.t0 > cur_e:
                if cur_e is not None:
                    busy += cur_e - cur_s
                cur_s, cur_e = w.t0, w.t1
            else:
                cur_e = max(cur_e, w.t1)
        busy += cur_e - cur_s
        spans = {}
        for e in evs:
            if e.kind == "E" and e.name in WRAPPED:
                spans[e.name] = spans.get(e.name, 0.0) + (e.t1 - e.t0) * 1000
        inside = [f for f in flushes if any(w.t0 <= f.t0 and f.t1 <= w.t1 + 1e-6 for w in works)]
        paint = min((f.t1 for f in inside), default=None)
        return {
            "queue_ms": max(0.0, (first.t0 - t_send) * 1000),
            "paint_ms": (paint - t_send) * 1000 if paint else None,
            "settle_ms": (max(w.t1 for w in works) - t_send) * 1000,
            "busy_ms": busy * 1000,
            "frames": len(inside),
            "bytes": sum(f.arg for f in inside),
            "timeline": [(e.name, (e.t0 - t_send) * 1000, (e.t1 - e.t0) * 1000) for e in evs
                         if e.kind == "E" and e.name in WRAPPED and e.name != "_tui._draw_pane_buf"][:120],
            "frame_src": [(f.chain, f.arg) for f in inside],
            "panes": _pane_costs(evs),
            "spans": spans,   # real wall ms per wrapped function: ground truth for the calibration check
        }

    def perform(self, step):
        """Runs one scenario step; returns a metrics dict (see measure_since)."""
        if self.forward:
            self.forward(("label", step.group, int(now() * 1e6), step.all_work))
        mark = len(self.events)
        cpu0 = self.cpu_seconds()
        t_send = now()
        res = {"group": step.group, "detail": step.detail, "t_send": t_send}
        kind, payload = step.kind, step.payload
        if kind == "idle":
            self.pump(payload)
            fl = [e for e in self.events[mark:] if e.kind == "E" and e.name == "_tui._flush"]
            dt = now() - t_send
            res.update(idle_s=dt, frames=len(fl), bytes=sum(f.arg for f in fl), frame_src=[(f.chain, f.arg) for f in fl], settle_ms=dt * 1000,
                       busy_ms=sum((f.t1 - f.t0) for f in fl) * 1000, queue_ms=0.0, paint_ms=None)
        else:
            if kind == "click_text":
                pos = self.locate(payload)
                if pos is None:
                    res.update(ok=False, note=f"'{payload}' not on screen")
                    return res
                payload = _click(pos[0] + 1, pos[1])
            t_last, out0, presses = t_send, self.out_bytes, []
            if kind == "resize":
                self.resize(*payload)
            elif kind == "repeat":
                # a held key: one press per repeat interval; the pause keeps reading the app's output like a terminal
                key, count, gap = payload
                for i in range(count):
                    t_last = now()
                    presses.append(t_last)
                    self.send(key)
                    self.pump(gap, until=lambda: not self.alive)
            else:
                self.send(payload)
            if self.probes:
                done = lambda: (not self.alive) or (
                    self.open_work == 0 and len(self.events) > mark and self.last_work_end >= t_send - 0.001
                    and now() - self.last_work_end >= step.quiet and (kind != "repeat" or now() - self.last_out >= step.quiet))
                ok = self.pump(step.timeout, until=done)
                m = self.measure_since(mark, t_send) or {}
                if kind == "repeat" and m:
                    # per press: sent -> handled by the loop (queue) -> first output the terminal receives after it was handled
                    # (paint). A press the app coalesced into a later one is paired with the handler that took it.
                    handled = sorted((e for e in self.events[mark:] if e.kind == "E" and e.name == "_tui_input.key_event"), key=lambda e: e.t0)
                    flushes = sorted(e.t1 for e in self.events[mark:] if e.kind == "E" and e.name == "_tui._flush")
                    arrivals = [t for t in self.out_times if t >= t_send]   # widgets such as lists and inputs draw outside _tui._flush
                    queue, lag = [], []
                    for i, tp in enumerate(presses):
                        h = handled[min(i, len(handled) - 1)] if handled else None
                        if h is None:
                            continue
                        painted = next((t for t in arrivals if t >= h.t0), h.t1)
                        queue.append(max(0.0, h.t0 - tp) * 1000)
                        lag.append(max(0.0, painted - tp) * 1000)
                    tail = max(0.0, (self.last_out - t_last) * 1000)
                    if lag:
                        lag.sort()
                        m.update(press_n=len(lag), handled_n=len(handled), queue_ms=sum(queue) / len(queue),
                                 lag_med_ms=lag[len(lag) // 2], lag_max_ms=lag[-1], tail_ms=tail)
                        m["settle_ms"] = lag[-1]
                    # render cadence: mean gap between consecutive frames of the hold (the repeat interval when it keeps up)
                    m["frame_gap_ms"] = ((flushes[-1] - flushes[0]) / (len(flushes) - 1) * 1000) if len(flushes) > 1 else None
                    m["out_bytes"] = self.out_bytes - out0
                res.update(m)
                res["ok"] = bool(m) and ok
                res["went"] = any(e.kind == "E" and e.name == "tui.goto" for e in self.events[mark:])
                if step.group == "shutdown":
                    dt = (now() - t_send) * 1000
                    res.update(settle_ms=dt, busy_ms=dt, queue_ms=0.0, paint_ms=None, ok=not self.alive)
            else:
                # traced: no probes, so wait a multiple of what the untraced run needed
                self.pump(step.wait, until=lambda: not self.alive)
                res["ok"] = True
        if step.expect and res.get("ok") is not False and self.locate(step.expect) is None:
            res.update(ok=False, note=f"expected '{step.expect}' on screen after the step, not found")
        res["cpu_ms"] = (self.cpu_seconds() - cpu0) * 1000
        res["rss_kb"] = self.rss_kb()
        res["alive"] = self.alive
        res["t_end"] = now()
        if self.forward:
            self.forward(("label_end", int(now() * 1e6)))
        return res
