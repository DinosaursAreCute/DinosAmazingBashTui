"""Live view of the app under test: its raw terminal output replayed in a second window of the test size.

The session keeps owning the pty (TIOCSWINSZ sets the size the app sees); this window only replays the bytes through
a FIFO. On Hyprland the window floats at the exact pixel size of rows x cols cells, on another monitor when there is
one, so the profiler's own terminal stays visible next to it. Elsewhere a plain terminal window is opened, or the
`cat` command to run by hand is printed. Replaying costs a write per pty read: a watched run is for looking, not for
comparing timings."""
import fcntl
import json
import os
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

EMULATORS = ("kitty", "ghostty", "alacritty")


def _cell_px():
    """(w, h) of one cell in this terminal, from its pixel size; a fallback when it does not report one."""
    try:
        rows, cols, xp, yp = struct.unpack("HHHH", fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b"\0" * 8))
        if xp and yp and cols and rows:
            return xp / cols, yp / rows
    except OSError:
        pass
    return 10.0, 22.0


def _hypr(*args):
    try:
        return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def _other_monitor():
    """Name of a monitor that is not the focused one, or None."""
    try:
        mons = json.loads(_hypr("monitors", "-j") or "[]")
    except ValueError:
        return None
    for m in mons:
        if not m.get("focused"):
            return m.get("name")
    return None


def _kitty_font_size():
    """The font size (points) kitty is configured with (its default, 11, when the config does not set one)."""
    try:
        out = subprocess.run(["kitty", "--debug-config"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return 11.0
    for line in out.splitlines():
        if line.startswith("font_size"):
            try:
                return float(line.split()[1])
            except (IndexError, ValueError):
                break
    return 11.0


def _monitor_room(name):
    """(width, height) in pixels of the named monitor (the focused one when None) minus the bars the compositor reserves."""
    try:
        mons = json.loads(_hypr("monitors", "-j") or "[]")
    except ValueError:
        return None
    for m in mons:
        if (name and m.get("name") == name) or (not name and m.get("focused")):
            left, top, right, bottom = m.get("reserved", [0, 0, 0, 0])
            return (m["width"] - left - right) / m.get("scale", 1) - 16, (m["height"] - top - bottom) / m.get("scale", 1) - 16
    return None


def _viewer_cmd(exe, show, cls=None, font=None):
    """The terminal emulator command that runs `show`; `cls` names its window so the compositor can find it, `font` is a
    kitty font size override."""
    tag = [] if not cls else ["--class=" + cls] if exe == "ghostty" else ["--class", cls]
    if font and exe == "kitty":
        tag += ["-o", f"font_size={font}"]
    return [exe, *tag, *show.split()] if exe == "kitty" else [exe, *tag, "-e", *show.split()]


def _viewer_script(fifo, szfile):
    """Shell run in the viewer: echo off (the mouse reports the terminal sends while the app tracks the mouse must not be
    printed into the picture), its own size written to `szfile` at start and on every resize, then the FIFO replayed."""
    return (f"stty -echo; trap 'stty size >{szfile}' WINCH; stty size >{szfile}; cat {fifo} & p=$!; "
            "while kill -0 $p 2>/dev/null; do wait $p; done")


def _viewer_size(szfile):
    try:
        with open(szfile) as f:
            r, c = f.read().split()
        return int(r), int(c)
    except (OSError, ValueError):
        return None


def _hypr_window(cls, rows, cols, w, h, szfile, wait=4.0):
    """Hyprland (lua config): find the viewer window by class, un-maximize it (a terminal may start maximized and then
    ignores size), and resize it until the viewer reports exactly rows x cols cells (the viewer's font is not this
    terminal's, so the pixel guess w x h is corrected from what it reports), then centre it."""
    end = time.time() + wait
    while time.time() < end:
        try:
            clients = json.loads(_hypr("clients", "-j") or "[]")
        except ValueError:
            clients = []
        win = next((c for c in clients if c.get("class") == cls), None)
        if win:
            sel = f'window="address:{win["address"]}"'
            for _ in range(8):   # the terminal maximizes itself once mapped: apply, look, correct, apply again
                time.sleep(0.3)
                _hypr("dispatch", f'hl.dsp.window.fullscreen_state({{internal=0, client=0, action="set", {sel}}})')
                _hypr("dispatch", f"hl.dsp.window.resize({{x={w}, y={h}, {sel}}})")
                time.sleep(0.3)
                got = _viewer_size(szfile)
                try:
                    cur = next(c for c in json.loads(_hypr("clients", "-j")) if c.get("class") == cls)["size"]
                except (ValueError, StopIteration):
                    return None
                if got and got != (rows, cols) and got[0] and got[1] and cur == [w, h]:
                    w += round((cols - got[1]) * w / got[1]) + (1 if got[1] < cols else 0)
                    h += round((rows - got[0]) * h / got[0]) + (1 if got[0] < rows else 0)
                elif got == (rows, cols):
                    break
            _hypr("dispatch", f"hl.dsp.window.center({{{sel}}})")
            return sel, w, h
        time.sleep(0.1)
    return None


class Watch:
    def __init__(self, rows, cols):
        self.fd = None
        self.fifo = os.path.join(tempfile.mkdtemp(prefix="dprof-watch-"), "out")
        os.mkfifo(self.fifo)
        szfile = self.fifo + ".size"
        script = self.fifo + ".sh"   # a file: the command goes through a lua string, which has no room for quotes
        with open(script, "w") as f:
            f.write(_viewer_script(self.fifo, szfile))
        show = "sh " + script
        exe = next((e for e in EMULATORS if shutil.which(e)), None)
        hypr = bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")) and shutil.which("hyprctl")
        if exe and hypr:
            self._hypr_view(exe, show, szfile, rows, cols)
        elif exe:
            flags = {"kitty": ["--override", f"initial_window_width={cols}c", "--override", f"initial_window_height={rows}c"],
                     "alacritty": ["-o", f"window.dimensions.columns={cols}", "-o", f"window.dimensions.lines={rows}"],
                     "ghostty": [f"--window-width={cols}", f"--window-height={rows}"]}[exe]
            cmd = _viewer_cmd(exe, show)
            subprocess.Popen([cmd[0], *flags, *cmd[1:]], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        else:
            print(f"watch: no known terminal emulator; run in a {cols}x{rows} terminal:  sh {script}", file=sys.stderr)
        self.fd = self._open_when_read()
        self.size(rows, cols)

    def _hypr_view(self, exe, show, szfile, rows, cols):
        """Open the viewer so that it shows rows x cols cells. When that needs more pixels than the monitor has, reopen it
        with a smaller font (kitty) instead of letting the screen crop the picture."""
        cw, ch = _cell_px()
        w, h = int(cols * cw) + 24, int(rows * ch) + 24   # a first guess, corrected from what the viewer reports
        mon = _other_monitor()
        font = None
        for attempt in range(2):
            cls = f"dprof-watch-{os.getpid()}-{attempt}"
            cmd = shlex.join(_viewer_cmd(exe, show, cls, font))
            opts = "{float=true" + (f', monitor="{mon}"' if mon else "") + "}"
            _hypr("dispatch", f'hl.dsp.exec_cmd("{cmd}", {opts})')
            got = _hypr_window(cls, rows, cols, w, h, szfile)
            avail = _monitor_room(mon)
            if not got or exe != "kitty" or not avail or attempt:
                return
            sel, w, h = got
            scale = min(avail[0] / w, avail[1] / h) * 0.97
            base = _kitty_font_size()
            if scale >= 1 or not base:
                return
            font = max(4.0, int(base * scale * 2) / 2)   # half-point steps, rounded down
            _hypr("dispatch", f"hl.dsp.window.close({{{sel}}})")
            time.sleep(0.3)
            w, h = int(w * font / base), int(h * font / base)   # pixel guess for the smaller font; corrected again

    def _open_when_read(self, wait=8.0):
        """The FIFO's write end, once the viewer reads it; None (watching off) if no viewer shows up."""
        end = time.time() + wait
        while time.time() < end:
            try:
                fd = os.open(self.fifo, os.O_WRONLY | os.O_NONBLOCK)   # ENXIO until a reader exists
                os.set_blocking(fd, True)
                return fd
            except OSError:
                time.sleep(0.05)
        print("watch: the viewer window did not start; continuing without it", file=sys.stderr)
        return None

    def write(self, data):
        if self.fd is not None:
            try:
                os.write(self.fd, data)
            except OSError:   # viewer closed
                self.fd = None

    def size(self, rows, cols):
        """New session or resize: reset the screen, and ask the window to follow (terminals may ignore it)."""
        self.write(b"\x1bc" + f"\x1b[8;{rows};{cols}t".encode())
