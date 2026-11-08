"""A pty session whose output is timestamped the instant it is read, and an offline terminal emulator that replays it.

Why two parts: timing must not depend on how slow the emulator is. The reader thread does nothing but read, stamp
(perf_counter_ns) and store; the emulator (pyte) replays the stored chunks later, in order, and reports at which chunk the
*visible* screen changed or satisfied a predicate. With a 100 us switch interval the GIL never delays the stamp by more than that."""
import fcntl
import os
import pty
import re
import select
import signal
import struct
import sys
import termios
import threading
import time

import pyte

WATCH = None  # a watch.Watch mirroring all output into a viewer window (compare.py --watch), else None
SYNC_ON, SYNC_OFF = b"\x1b[?2026h", b"\x1b[?2026l"
# Modes a modern terminal (kitty, ghostty, foot, wezterm) reports as supported when queried with DECRQM.
KNOWN_MODES = {1, 7, 25, 1000, 1002, 1003, 1004, 1006, 1015, 1049, 2004, 2026}
_KITTY = re.compile(rb"\x1b\[([<>=])(\d*)(?:;(\d+))?u")  # kitty keyboard protocol: push (>), pop (<), set (=)
_QUERY = re.compile(rb"\x1b\[([?>]?)([0-9;]*)(\$p|c|n)")


def terminal_replies(data):
    """Answers a real terminal would send for the queries in data (device attributes, status, DECRQM). Without them an
    app may wait for a timeout or fall back to a slower path, which would be measured as the app's own latency."""
    out = []
    for prefix, arg, final in _QUERY.findall(data):
        if final == b"c" and prefix != b"?":
            out.append(b"\x1b[>1;10;0c" if prefix == b">" else b"\x1b[?62;22c")
        elif final == b"n":
            out.append(b"\x1b[0n" if arg == b"5" else (b"\x1b[?1;1R" if prefix == b"?" else b"\x1b[1;1R"))
        elif final == b"$p" and prefix == b"?" and arg.isdigit():
            out.append(b"\x1b[?%s;%d$y" % (arg, 2 if int(arg) in KNOWN_MODES else 0))
    return b"".join(out)


class Session:
    """The app running in a pty. `events` is a list of (t_ns, bytes) in arrival order."""

    def __init__(self, argv, env, cwd, rows, cols, cpus=None, replies=True, keyboard="auto"):
        self.rows, self.cols, self.replies, self.keyboard = rows, cols, replies, keyboard
        self.kitty_stack = []  # flags the app pushed with CSI > N u; empty = legacy keyboard
        self.events = []
        self.eof = False
        self.last_send = (0, 0)
        self._stop = False
        sys.setswitchinterval(1e-4)
        if WATCH:
            WATCH.size(rows, cols)
        self.t_spawn = time.perf_counter_ns()
        pid, fd = pty.fork()
        if pid == 0:
            try:
                if cpus:
                    os.sched_setaffinity(0, cpus)
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
                os.chdir(cwd)
                os.execvpe(argv[0], argv, env)
            finally:
                os._exit(127)
        self.pid, self.fd = pid, fd
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._thread.start()

    def _read_loop(self):
        fd = self.fd
        while not self._stop:
            r, _, _ = select.select([fd], [], [], 0.05)
            if not r:
                continue
            try:
                data = os.read(fd, 1 << 16)
            except OSError:
                data = b""
            t = time.perf_counter_ns()
            if not data:
                self.eof = True
                return
            self.events.append((t, data))
            if b"u" in data:
                self._track_keyboard(data)
            if self.replies:
                rep = terminal_replies(data)
                if rep:
                    try:
                        os.write(fd, rep)
                    except OSError:
                        pass
            if WATCH:  # last, after every timestamp is taken
                WATCH.write(data)

    def _track_keyboard(self, data):
        for mode, n, m in _KITTY.findall(data):
            if mode == b">":
                self.kitty_stack.append(int(n or 0))
            elif mode == b"<":
                del self.kitty_stack[-(int(n or 1)):]
            elif self.kitty_stack:
                self.kitty_stack[-1] = int(n or 0)

    @property
    def kitty_keys(self):
        """True while the app has asked for disambiguated keys (flag 1) and the run lets the terminal comply."""
        return self.keyboard == "auto" and bool(self.kitty_stack) and bool(self.kitty_stack[-1] & 1)

    def send(self, data):
        if self.kitty_keys and getattr(data, "kitty", b""):
            data = data.kitty  # what a kitty-protocol terminal sends for this chord
        self.last_send = (time.perf_counter_ns(), len(self.events))  # (when, events seen so far): lets a step time from its LAST input
        os.write(self.fd, data)

    def set_size(self, rows, cols):
        self.rows, self.cols = rows, cols
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        if WATCH:
            WATCH.size(rows, cols)

    def close(self):
        self._stop = True
        for target in (lambda: os.killpg(self.pid, signal.SIGKILL), lambda: os.kill(self.pid, signal.SIGKILL)):
            try:
                target()
                break
            except OSError:
                continue
        try:
            os.waitpid(self.pid, 0)
        except OSError:
            pass
        self._thread.join(1)
        try:
            os.close(self.fd)
        except OSError:
            pass


class Emulator:
    """Replays chunks into a virtual screen and says whether each chunk changed what the user can see.
    Output inside a synchronized-update block (CSI ? 2026 h ... l) is invisible until the block ends, exactly as in a real terminal."""

    def __init__(self, rows, cols):
        self.screen = pyte.Screen(cols, rows)
        self.stream = pyte.ByteStream(self.screen)
        self.hashes = [None] * rows
        self.sync = False

    def resize(self, rows, cols):
        self.screen.resize(rows, cols)
        self.hashes = [None] * rows
        self.screen.dirty.update(range(rows))

    def feed(self, data):
        """Returns True if the visible screen (text, colours, attributes) differs after this chunk."""
        self.stream.feed(data)
        on, off = data.rfind(SYNC_ON), data.rfind(SYNC_OFF)
        if on >= 0 or off >= 0:
            self.sync = on > off
        if self.sync:
            return False
        s, changed, default = self.screen, False, self.screen.default_char
        for y in s.dirty:
            if y < len(self.hashes):
                h = hash(tuple((x, c) for x, c in sorted(s.buffer[y].items()) if c != default))
                if h != self.hashes[y]:
                    self.hashes[y], changed = h, True
        s.dirty.clear()
        return changed
