"""Streaming xtrace aggregator.

The app runs with `set -x` and a PS4 that prints `@<epoch>|<pid>|<file>:<line>|<call stack>|`,
so every executed command becomes one line on a pipe. This module folds that stream into
per-scenario statistics while the app is still running (a cold start is ~2M lines, far too
much to keep on disk).

Attribution model: wall-clock time between two consecutive trace lines belongs to the
*earlier* line (xtrace prints a command before it runs). Each gap is then classified:

    sh     bash executing builtins / functions            (inflated by tracing: calibrated later)
    ex     an external program running                    (real time, not inflated)
    fk     process creation / reaping across a pid change (real time)
    idle   blocked in `read`/`sleep` waiting for input
    wait   blocked in `wait`
    probe  the profiler's own wrapper lines

Scenario windows and "the app is doing work for the user" intervals arrive as driver
messages, merged by timestamp behind a watermark so no line is attributed before the
message that says which scenario it belongs to.
"""
import collections
import multiprocessing as mp
import os
import shutil
import threading
import time

from .scenarios import FOCUS_ROOTS

BUILTINS = set(
    "alias bg bind break builtin caller cd command compgen complete compopt continue declare dirs disown echo "
    "enable eval exec exit export false fc fg getopts hash help history jobs kill let local logout mapfile "
    "popd printf pushd pwd read readarray readonly return set shift shopt source suspend test times trap true "
    "type typeset ulimit umask unalias unset wait [ [[ (( . : ! { } if then else elif fi for while until do "
    "done case esac in function select time coproc".split()
)
BUILTINS_B = {w.encode() for w in BUILTINS}
# A call stack containing one of these is the app answering the user; anything else in an
# interaction window is ambient (idle ticks, footer clock...).
WORK_FRAMES = {"_tui_input.key_event", "_tui._handle_mouse", "_tui._apply_resize", "tui.goto", "tui.render",
               "tui.hook.fire", "_tui._flush_pending_render", "_master_cleanup"}
KINDS = ("sh", "ex", "fk", "idle", "wait", "probe")


class Bucket:
    __slots__ = ("stacks", "lines", "calls", "edges", "forks", "execs", "tot", "nlines", "pids", "focus")

    def __init__(self):
        self.stacks = {}   # (stack id, kind key) -> [us, n]
        self.lines = {}    # "file:line" -> [sh_us, ex_us, fk_us, hits]
        self.calls = collections.Counter()
        self.edges = collections.Counter()
        self.forks = collections.Counter()   # (function, "file:line") -> new subshells
        self.execs = {}    # (word, function) -> [count, us]
        self.tot = dict.fromkeys(KINDS, 0)
        self.nlines = 0
        self.pids = set()
        self.focus = {}    # (FOCUS_ROOTS function, "file:line") -> [sh_us, ex_us, fk_us, hits], whatever runs below it


class Aggregator:
    def __init__(self, wrapped):
        self.wrapped = {w.encode() for w in wrapped}
        self.buckets = {}
        self.stack_ids = {}      # raw stack bytes -> sid
        self.stack_info = []     # sid -> (frames tuple, top_is_probe)
        self.stack_roots = {}    # sid -> the FOCUS_ROOTS present in that stack (computed once per stack)
        self.work_sid = []       # sid -> does this stack belong to answering the user
        self.funcs = set()
        self.funcfile = {}
        self.cls_cache = {}
        # scenario state
        self.label = None
        self.all_work = False
        self.concurrent = False  # cache-build workers interleave: a pid change is then not a fork
        self.evq = collections.deque()
        # previous line
        self.prev = None
        self.last_frames = {}    # pid -> frames tuple
        self.seen_pids = set()
        self.pid_last = {}       # pid -> (sid, "file:line") of its most recent line
        self.total_lines = 0
        self.first_ts = 0
        self.last_ts = 0

    # ── helpers ──────────────────────────────────────────────────────────────
    def _stack(self, raw):
        sid = self.stack_ids.get(raw)
        if sid is not None:
            return sid
        names = raw.decode("utf-8", "replace").split(" ") if raw else []
        probe_top = bool(names) and names[0].encode() in self.wrapped
        frames = []
        for n in reversed(names):
            if n.startswith("__prof_orig_"):
                real = n[12:]
                if frames and frames[-1] == real:
                    continue
                n = real
            frames.append(n)
        if not frames:
            frames = ["⟨main⟩"]
        self.funcs.update(frames)
        sid = len(self.stack_info)
        self.stack_info.append((tuple(frames), probe_top))
        work = any(f in WORK_FRAMES for f in frames)
        if not work and "_tui_layer.draw_all" in frames:   # overlay redraw: ambient only when the main loop itself asks
            i = frames.index("_tui_layer.draw_all")
            work = i > 0 and frames[i - 1] != "tui.run"
        self.work_sid.append(work)
        self.stack_ids[raw] = sid
        return sid

    def _classify(self, word):
        c = self.cls_cache.get(word)
        if c is not None:
            return c
        w = word.decode("utf-8", "replace")
        if word == b"read":
            c = "read"
        elif word == b"wait":
            c = "wait"
        elif word in (b"sleep",):
            c = "idle"
        elif w in self.funcs or word in BUILTINS_B or b"=" in word or word[:1] in (b"(", b"[", b">", b"<"):
            c = "sh"
        elif shutil.which(w):
            c = "ex"
        else:
            c = "sh"
        self.cls_cache[word] = c
        return c

    def _bucket(self, sid):
        if self.label is None:
            key = "-|a"
        elif self.all_work or self.work_sid[sid]:
            key = self.label + "|w"
        else:
            key = self.label + "|a"
        b = self.buckets.get(key)
        if b is None:
            b = self.buckets[key] = Bucket()
        return b

    def _apply_events(self, ts):
        evq = self.evq
        while evq and evq[0][0] <= ts:
            _, kind, a, b = evq.popleft()
            if kind == "label":
                self.label, self.all_work = a, b
                self.concurrent = a == "startup.cold"
            elif kind == "label_end":
                self.label, self.all_work = None, False

    # ── the hot loop ─────────────────────────────────────────────────────────
    def feed(self, lines, watermark):
        """Consumes trace lines (bytes) whose timestamp is <= watermark (us).
        Returns the unconsumed tail (lines newer than the watermark)."""
        prev = self.prev
        stack_ids, stack_info, cls_cache = self.stack_ids, self.stack_info, self.cls_cache
        i, n = 0, len(lines)
        while i < n:
            ln = lines[i]
            if not ln.startswith(b"@"):
                i += 1
                continue
            p = ln.split(b"|", 4)
            if len(p) < 5:
                i += 1
                continue
            try:
                ts = int(p[0].lstrip(b"@").replace(b".", b"").replace(b",", b""))
            except ValueError:
                i += 1
                continue
            if ts > watermark:
                break
            i += 1
            pid, src, raw, cmd = p[1], p[2], p[3], p[4]
            sid = stack_ids.get(raw)
            if sid is None:
                sid = self._stack(raw)
            frames, probe_top = stack_info[sid]
            word = cmd.split(b" ", 1)[0]
            cls = cls_cache.get(word)
            if cls is None:
                cls = self._classify(word)

            if prev is not None:
                pts, psid, pcls, pword, psrc, ppid, pbucket, pprobe = prev
                dur = ts - pts
                if dur < 0:
                    dur = 0
                if pprobe:
                    kind = "probe"
                elif pcls == "read":
                    kind = "idle" if dur > 5000 else "sh"
                elif pcls == "idle":
                    kind = "idle"
                elif pcls == "wait":
                    kind = "wait"
                elif pcls == "ex":
                    kind = "ex"
                elif ppid != pid and (not self.concurrent or pid not in self.seen_pids):
                    kind = "fk"
                else:
                    kind = "sh"
                if kind == "fk" and pid in self.pid_last:
                    # child finished, parent resumes: the reaping cost belongs to the forking function
                    psid, psrc = self.pid_last[pid]
                pbucket.tot[kind] += dur
                pbucket.nlines += 1
                if kind != "probe":
                    kk = kind if kind != "ex" else "ex:" + pword.decode("utf-8", "replace")
                    key = (psid, kk)
                    e = pbucket.stacks.get(key)
                    if e is None:
                        pbucket.stacks[key] = [dur, 1]
                    else:
                        e[0] += dur
                        e[1] += 1
                    if kind in ("sh", "ex", "fk"):
                        roots = self.stack_roots.get(psid)
                        if roots is None:
                            fr = stack_info[psid][0]
                            roots = self.stack_roots[psid] = tuple(r for r in FOCUS_ROOTS if r in fr)
                        for r in roots:
                            fe = pbucket.focus.get((r, psrc))
                            if fe is None:
                                fe = pbucket.focus[(r, psrc)] = [0, 0, 0, 0]
                            fe[0 if kind == "sh" else 1 if kind == "ex" else 2] += dur
                            fe[3] += 1
                        ls = pbucket.lines.get(psrc)
                        if ls is None:
                            ls = pbucket.lines[psrc] = [0, 0, 0, 0]
                        ls[0 if kind == "sh" else 1 if kind == "ex" else 2] += dur
                        ls[3] += 1
                    if kind == "ex":
                        ek = (pword, stack_info[psid][0][-1])
                        ex = pbucket.execs.get(ek)
                        if ex is None:
                            pbucket.execs[ek] = [1, dur]
                        else:
                            ex[0] += 1
                            ex[1] += dur
            else:
                self.first_ts = ts

            self._apply_events(ts)
            bucket = self._bucket(sid)

            if pid not in self.seen_pids:
                if self.seen_pids:
                    bucket.forks[(frames[-1], src.decode("utf-8", "replace"))] += 1
                self.seen_pids.add(pid)
                base = prev and stack_info[prev[1]][0] or ()
                self.last_frames[pid] = base
            bucket.pids.add(pid)
            last = self.last_frames[pid]
            if last is not frames:
                cp, m = 0, min(len(last), len(frames))
                while cp < m and last[cp] == frames[cp]:
                    cp += 1
                for j in range(cp, len(frames)):
                    bucket.calls[frames[j]] += 1
                    if j:
                        bucket.edges[(frames[j - 1], frames[j])] += 1
                self.last_frames[pid] = frames
                if not probe_top and frames[-1] not in self.funcfile:
                    self.funcfile[frames[-1]] = src.split(b":")[0].decode("utf-8", "replace")
            srcs = src.decode("utf-8", "replace")
            self.pid_last[pid] = (sid, srcs)
            prev = (ts, sid, cls, word, srcs, pid, bucket, probe_top)
            self.total_lines += 1
            self.last_ts = ts
        self.prev = prev
        return lines[i:]

    def result(self):
        out = {"buckets": {}, "funcfile": self.funcfile, "lines": self.total_lines,
               "span_us": self.last_ts - self.first_ts}
        for key, b in self.buckets.items():
            out["buckets"][key] = {
                "stacks": {(self.stack_info[sid][0], kk): v for (sid, kk), v in b.stacks.items()},
                "lines": b.lines, "calls": dict(b.calls), "edges": dict(b.edges),
                "forks": dict(b.forks), "focus": dict(b.focus),
                "execs": {(w.decode("utf-8", "replace"), f): v for (w, f), v in b.execs.items()},
                "tot": b.tot, "nlines": b.nlines, "pids": len(b.pids),
            }
        return out


def _worker(rfd, conn, wrapped, progress):
    agg = Aggregator(wrapped)
    chunks = collections.deque()
    cv = threading.Condition()
    state = {"eof": False, "bytes": 0}

    def reader():
        while True:
            # crude backpressure so a stalled consumer cannot eat all memory
            while state["bytes"] > 400 << 20:
                time.sleep(0.02)
            try:
                d = os.read(rfd, 1 << 20)
            except OSError:
                d = b""
            with cv:
                if not d:
                    state["eof"] = True
                else:
                    chunks.append(d)
                    state["bytes"] += len(d)
                cv.notify()
            if not d:
                return

    threading.Thread(target=reader, daemon=True).start()
    watermark = 0
    stopping = False
    tail = b""
    pending = []
    last_prog = 0.0
    while True:
        while conn.poll(0):
            m = conn.recv()
            t = m[0]
            if t == "hb":
                watermark = max(watermark, int(m[1] * 1e6))
            elif t == "label":
                agg.evq.append((m[2], "label", m[1], m[3]))
            elif t == "label_end":
                agg.evq.append((m[1], "label_end", None, None))
            elif t == "stop":
                stopping = True
        with cv:
            got = list(chunks)
            chunks.clear()
            eof = state["eof"]
        if got:
            data = tail + b"".join(got)
            state["bytes"] -= sum(len(g) for g in got)
            *lines, tail = data.split(b"\n")
            pending.extend(lines)
        if pending:
            wm = (1 << 62) if stopping else watermark   # after `stop` no newer heartbeat will come
            pending = agg.feed(pending, wm)
        now = time.time()
        if now - last_prog > 0.25:
            last_prog = now
            progress.value = agg.total_lines
        if stopping and eof and not pending:
            break
        if stopping and not got and _deadline(state, bool(pending)):
            break
        if not got:
            conn.poll(0.01)
    agg.feed([], 0)
    progress.value = agg.total_lines
    conn.send(("result", agg.result()))


def _deadline(state, busy):
    """After `stop`, wait for EOF but not forever: a stray background worker may hold the pipe open."""
    if busy or "stop_at" not in state:
        state["stop_at"] = time.time()
    return time.time() - state["stop_at"] > 4.0


class Tracer:
    """Owns the trace pipe and the aggregator process for one traced session."""

    def __init__(self, wrapped):
        self.r, self.w = os.pipe()
        try:
            import fcntl
            fcntl.fcntl(self.w, 1031, 1 << 20)  # F_SETPIPE_SZ: fewer stalls for the app
        except (OSError, ImportError):
            pass
        ctx = mp.get_context("fork")
        self.parent_conn, child_conn = ctx.Pipe()
        self.progress = ctx.Value("q", 0)
        self.proc = ctx.Process(target=_worker, args=(self.r, child_conn, list(wrapped), self.progress), daemon=True)
        self.proc.start()
        os.close(self.r)

    @property
    def lines(self):
        return self.progress.value

    def send(self, msg):
        try:
            self.parent_conn.send(msg)
        except (OSError, BrokenPipeError):
            pass

    def release_write_end(self):
        """Parent drops its copy so EOF arrives once the app (and its children) exit."""
        try:
            os.close(self.w)
        except OSError:
            pass

    def finish(self, timeout=180):
        self.send(("stop",))
        t0 = time.time()
        while time.time() - t0 < timeout:
            if self.parent_conn.poll(0.1):
                kind, data = self.parent_conn.recv()
                self.proc.join(2)
                return data
            if not self.proc.is_alive():
                break
        return None
