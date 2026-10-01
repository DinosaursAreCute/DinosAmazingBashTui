#!/usr/bin/env python3
"""compare.py - black-box latency comparison of the DABT and Textual apps in tools/compare.

Both apps run in a hidden pseudo-terminal and get the same scripted session (page switches, clicks, typing,
list scrolling, resize, idle). Nothing inside either app is instrumented: a step is timed from the moment its
input is written to when bytes appear (feedback), when the expected text appears (content) and when output goes
quiet (done). CPU and RSS come from /proc for the app's whole process tree. Standard library only.

  tools/compare/compare.py                  # 5 rounds, both apps, 150x45
  tools/compare/compare.py --rounds 2       # quick
  tools/compare/compare.py --only dabt      # one side
  tools/compare/compare.py --size 120x40
Textual needs a venv: see tools/compare/README.md (COMPARE_VENV, default ~/.cache/dabt-compare-venv).
"""
import argparse
import fcntl
import json
import os
import pty
import select
import shutil
import signal
import statistics
import struct
import sys
import tempfile
import termios
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TICK = os.sysconf("SC_CLK_TCK")
QUIET = 0.15  # no output for this long = the frame is finished (neither app repaints while idle)
TIMEOUT = 8.0


def app_command(name):
    if name == "dabt":
        return ["bash", os.path.join(HERE, "dabt_app", "run.sh")]
    venv = os.environ.get("COMPARE_VENV", os.path.expanduser("~/.cache/dabt-compare-venv"))
    return [os.path.join(venv, "bin", "python"), os.path.join(HERE, "textual_app", "app.py")]


def tree_stats(root):
    """(cpu ms, rss kB) summed over root and all its descendants."""
    kids, stat = {}, {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat") as f:
                raw = f.read()
            rest = raw[raw.rindex(")") + 2:].split()
            pid, ppid = int(entry), int(rest[1])
            stat[pid] = int(rest[11]) + int(rest[12])
            kids.setdefault(ppid, []).append(pid)
        except (OSError, ValueError, IndexError):
            continue
    cpu = rss = 0
    todo = [root]
    while todo:
        pid = todo.pop()
        cpu += stat.get(pid, 0)
        todo.extend(kids.get(pid, ()))
        try:
            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        rss += int(line.split()[1])
        except OSError:
            pass
    return cpu * 1000 // TICK, rss


class Session:
    def __init__(self, name, home, rows, cols):
        self.name, self.home, self.rows, self.cols = name, home, rows, cols
        self.buf = bytearray()
        self.events = []  # (t, nbytes) since the last mark
        env = dict(os.environ, HOME=home, TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8", LANG="C.UTF-8")
        for k in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "TUI_HOME", "COLUMNS", "LINES"):
            env.pop(k, None)
        env["XDG_CONFIG_HOME"] = os.path.join(home, ".config")
        os.makedirs(env["XDG_CONFIG_HOME"], exist_ok=True)
        cmd = app_command(name)
        self.t_spawn = time.perf_counter()
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
            os.chdir(home)
            os.execvpe(cmd[0], cmd, env)
        self.pid, self.fd = pid, fd
        os.set_blocking(fd, False)

    def pump(self, seconds):
        end = time.perf_counter() + seconds
        while True:
            left = end - time.perf_counter()
            if left <= 0:
                return
            r, _, _ = select.select([self.fd], [], [], left)
            if r:
                self._read()

    def _read(self):
        try:
            data = os.read(self.fd, 65536)
        except (BlockingIOError, InterruptedError):
            return
        except OSError:
            data = b""
        if data:
            self.events.append((time.perf_counter(), len(data)))
            self.buf += data

    def mark(self):
        self.buf = bytearray()
        self.events = []

    def send(self, data):
        os.write(self.fd, data)

    def wait(self, expect=None, timeout=TIMEOUT):
        """Reads until `expect` shows up (if given) and the output has been quiet for QUIET seconds."""
        end = time.perf_counter() + timeout
        seen_at = None
        needle = expect.encode() if expect else None
        while time.perf_counter() < end:
            r, _, _ = select.select([self.fd], [], [], 0.01)
            if r:
                self._read()
            if needle and seen_at is None and needle in self.buf:
                seen_at = self.events[-1][0]
            if (needle is None or seen_at is not None) and self.events and time.perf_counter() - self.events[-1][0] >= QUIET:
                return seen_at
        return None

    def step(self, name, data, expect=None, settle=True):
        """One timed interaction. Returns a dict, or None fields if the expected text never appeared."""
        self.wait(None, QUIET)  # drain
        self.mark()
        cpu0, _ = tree_stats(self.pid)
        t0 = time.perf_counter()
        if isinstance(data, tuple):  # resize
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", data[0], data[1], 0, 0))
        else:
            self.send(data)
        seen = self.wait(expect, TIMEOUT if expect else 1.5)
        cpu1, _ = tree_stats(self.pid)
        ev = self.events
        ok = (expect is None) or seen is not None
        return {
            "step": name,
            "ok": ok,
            "feedback_ms": (ev[0][0] - t0) * 1000 if ev else None,
            "content_ms": ((seen - t0) * 1000 if seen else None) if expect else ((ev[0][0] - t0) * 1000 if ev else None),
            "done_ms": (ev[-1][0] - t0) * 1000 if ev else None,
            "bytes": sum(n for _, n in ev),
            "writes": len(ev),
            "cpu_ms": cpu1 - cpu0,
        }

    def close(self):
        try:
            os.killpg(self.pid, signal.SIGKILL)
        except OSError:
            try:
                os.kill(self.pid, signal.SIGKILL)
            except OSError:
                pass
        try:
            os.waitpid(self.pid, 0)
        except OSError:
            pass
        os.close(self.fd)


def click(x, y):
    return f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode()


def nav(index):
    """Click the menu button INDEX (1..4); both apps draw them on rows 2..5 of the menu pane."""
    return click(5, 1 + index)


def startup(name, home, rows, cols):
    """Spawn and wait for the first page. Returns (session, result)."""
    s = Session(name, home, rows, cols)
    seen = s.wait("Page 1: Buttons", timeout=30)
    cpu, rss = tree_stats(s.pid)
    done = s.events[-1][0] - s.t_spawn if s.events else None
    res = {"step": "startup", "ok": seen is not None, "feedback_ms": (s.events[0][0] - s.t_spawn) * 1000 if s.events else None,
           "content_ms": (seen - s.t_spawn) * 1000 if seen else None, "done_ms": done * 1000 if done else None,
           "bytes": sum(n for _, n in s.events), "writes": len(s.events), "cpu_ms": cpu}
    return s, res


def session_steps(s, rows, cols):
    out = []
    add = lambda *a, **k: out.append(s.step(*a, **k))
    add("nav.form", nav(2), "Page 2: Form")
    add("nav.data", nav(3), "Page 3: Data")
    add("nav.layout", nav(4), "Page 4: Layout")
    add("nav.buttons", nav(1), "Page 1: Buttons")
    add("nav.revisit", nav(2), "Page 2: Form")
    add("nav.revisit2", nav(1), "Page 1: Buttons")
    add("click.button", click(35, 6), "Clicks: 1")
    add("nav.form2", nav(2), "Page 2: Form")
    add("click.focus_input", click(40, 4))
    add("type.char", b"A")
    add("type.word", b"lice")
    add("click.submit", click(35, 9), "Hello, Alice")
    add("nav.data2", nav(3), "Page 3: Data")
    add("click.list", click(34, 4))
    add("key.down", b"\x1b[B", "Selected: Item 02")
    add("key.down_burst", b"\x1b[B" * 10, "Selected: Item 12")
    add("key.pagedown", b"\x1b[6~")
    add("nav.layout2", nav(4), "Page 4: Layout")
    add("click.advance", click(82, 4), "Progress: 10%")
    add("resize.small", (max(rows - 5, 20), max(cols - 30, 60)))
    add("resize.back", (rows, cols))
    t0 = time.perf_counter()
    cpu0, _ = tree_stats(s.pid)
    s.mark()
    s.pump(2.0)
    cpu1, rss = tree_stats(s.pid)
    out.append({"step": "idle.2s", "ok": True, "feedback_ms": None, "content_ms": None, "done_ms": None,
                "bytes": len(s.buf), "writes": len(s.events), "cpu_ms": cpu1 - cpu0})
    out.append({"step": "rss_kb", "ok": True, "bytes": rss, "feedback_ms": None, "content_ms": None, "done_ms": None, "writes": 0, "cpu_ms": 0})
    return out


def run_app(name, rounds, rows, cols):
    results = {}
    tmp = tempfile.mkdtemp(prefix=f"compare-{name}-")
    try:
        for r in range(rounds):
            cold_home = os.path.join(tmp, f"cold{r}")
            os.makedirs(cold_home)
            s, res = startup(name, cold_home, rows, cols)
            results.setdefault("startup.cold", []).append(res)
            s.close()
            s, res = startup(name, cold_home, rows, cols)  # same HOME: caches from the first run are warm
            results.setdefault("startup.warm", []).append(res)
            for st in session_steps(s, rows, cols):
                results.setdefault(st["step"], []).append(st)
            s.close()
            print(f"  {name}: round {r + 1}/{rounds} done", file=sys.stderr)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return results


def med(rows, key):
    vals = [x[key] for x in rows if x.get(key) is not None and x["ok"]]
    return statistics.median(vals) if vals else None


def summarize(results):
    return {step: {"ok": sum(1 for x in rows if x["ok"]), "n": len(rows),
                   **{k: med(rows, k) for k in ("feedback_ms", "content_ms", "done_ms", "bytes", "writes", "cpu_ms")}}
            for step, rows in results.items()}


def fmt(v, digits=0):
    return "-" if v is None else f"{v:.{digits}f}"


def report(summary, apps):
    lines = []
    head = f"{'step':<18}" + "".join(f"{a + ' content':>16}{a + ' done':>13}{a + ' bytes':>13}{a + ' cpu':>11}" for a in apps)
    if len(apps) == 2:
        head += f"{'content x':>11}"
    lines.append(head)
    steps = list(summary[apps[0]])
    for st in steps:
        row = f"{st:<18}"
        for a in apps:
            m = summary[a].get(st)
            if not m:
                row += f"{'-':>16}{'-':>13}{'-':>13}{'-':>11}"
                continue
            bad = "" if m["ok"] == m["n"] else f" ({m['ok']}/{m['n']})"
            if st == "rss_kb":
                row += f"{fmt(m['bytes'] / 1024, 1) + ' MB':>16}{'-':>13}{'-':>13}{'-':>11}"
            else:
                row += f"{fmt(m['content_ms'], 1) + bad:>16}{fmt(m['done_ms'], 1):>13}{fmt(m['bytes']):>13}{fmt(m['cpu_ms']):>11}"
        if len(apps) == 2:
            a, b = (summary[x].get(st) for x in apps)
            ca, cb = (m and (m["content_ms"] if st != "rss_kb" else m["bytes"]) for m in (a, b))
            row += f"{fmt(cb / ca, 2) + 'x':>11}" if ca and cb else f"{'-':>11}"
        lines.append(row)
    lines.append("")
    lines.append("times in ms, medians; content = input written -> expected text seen (first output byte if the step has none);")
    lines.append("done = last output byte before the screen went quiet; cpu = ms of CPU used by the app's process tree during the step;")
    lines.append("content x = textual / dabt (above 1 = DABT is faster); rss row compares MB; (k/n) = rounds in which the text appeared.")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--only", choices=("dabt", "textual"))
    ap.add_argument("--size", default="150x45")
    a = ap.parse_args()
    cols, rows = (int(x) for x in a.size.split("x"))
    apps = [a.only] if a.only else ["dabt", "textual"]
    for name in apps:
        if not os.path.exists(app_command(name)[0]) and name == "textual":
            sys.exit("textual venv missing: see tools/compare/README.md")
    raw, summary = {}, {}
    for name in apps:
        print(f"{name}:", file=sys.stderr)
        raw[name] = run_app(name, a.rounds, rows, cols)
        summary[name] = summarize(raw[name])
    text = report(summary, apps)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out = os.path.join(HERE, "reports", stamp)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "compare.json"), "w") as f:
        json.dump({"size": a.size, "rounds": a.rounds, "summary": summary, "raw": raw}, f, indent=1)
    with open(os.path.join(out, "compare.txt"), "w") as f:
        f.write(text + "\n")
    print(text)
    print(f"\nsaved {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
