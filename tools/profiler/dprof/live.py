"""Live progress: a scrolling log of finished steps (each with its own stamp and duration) above a
small in-place footer showing what is running right now, phase progress, ETA and trace throughput."""
import sys
import threading
import time

from . import term
from .term import c, pad, vlen, fmt_ms, fmt_bytes, fmt_num
from .scenarios import GROUP_INFO
from .analyze import rate

SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"


def mmss(sec):
    sec = max(0, sec)
    return f"{int(sec // 60):02d}:{sec % 60:04.1f}"


def eta_str(sec):
    sec = int(max(0, sec))
    return f"{sec // 60}:{sec % 60:02d}"


class NullLive:
    def phase(self, *a, **k): pass
    def warn(self, *a): pass
    def step_begin(self, *a): pass
    def step_end(self, *a): pass
    def note(self, *a): pass
    def set_tracer(self, *a): pass


class LiveUI:
    FOOT = 4

    def __init__(self, phases, out=None, tty=None):
        """phases: [(key, label, weight_per_step, steps)] - weights let traced (slower) steps count for more."""
        self.out = out or sys.stdout
        self.tty = term.is_tty() if tty is None else tty
        self.phases = phases
        self.total_weight = sum(w * n for _, _, w, n in phases) or 1
        self.done_weight = 0.0
        self.pi = -1
        self.phase_label = ""
        self.phase_steps = 0
        self.phase_done = 0
        self.t_start = time.time()
        self.cur = None
        self.cur_t0 = 0.0
        self.tracer = None
        self.trace_samples = []
        self.slowest = None
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.frame = 0
        self.drawn = False
        self.weight = 1.0
        self._th = None
        self._last_lines = 0
        self._last_t = time.time()

    # ── lifecycle ────────────────────────────────────────────────────────────
    def begin(self, banner_lines):
        for ln in banner_lines:
            self._print(ln)
        if self.tty:
            self._th = threading.Thread(target=self._loop, daemon=True)
            self._th.start()

    def finish(self):
        self.stop.set()
        if self._th:
            self._th.join(1)
        with self.lock:
            self._clear_footer()

    def phase(self, key, detail="", steps=None):
        with self.lock:
            idx = next((i for i, p in enumerate(self.phases) if p[0] == key), self.pi + 1)
            self.pi = idx
            _, label, w, n = self.phases[idx]
            self.phase_label = label + (f" · {detail}" if detail else "")
            self.weight, self.phase_steps, self.phase_done = w, (steps or n), 0
            self.cur = None
            self._log(f"{c('▌', 'cyan')} {c(self.phase_label, 'white', bold=True)}  "
                      f"{c(f'phase {idx + 1}/{len(self.phases)}', 'dim')}")

    # ── runner callbacks ─────────────────────────────────────────────────────
    def step_begin(self, desc):
        with self.lock:
            self.cur, self.cur_t0 = desc, time.time()

    def step_end(self, desc, res):
        now = time.time()
        with self.lock:
            dt = now - (self.cur_t0 or now)
            self.cur = None
            self.phase_done += 1
            self.done_weight += self.weight
            line = self._format_step(desc, res, dt, now)
            self._log(line)

    def note(self, text):
        with self.lock:
            self._log(f"  {c('•', 'cyan')} {c(text, 'dim')}")

    def warn(self, text):
        with self.lock:
            self._log(f"  {c('!', 'yellow', bold=True)} {c(text, 'yellow')}")

    def set_tracer(self, tracer):
        self.tracer = tracer
        self.trace_samples = []

    # ── formatting ───────────────────────────────────────────────────────────
    def _format_step(self, desc, res, dt, now):
        group = res.get("group", "")
        info = GROUP_INFO.get(group)
        ok = res.get("ok", True) is not False
        glyph = c("✓", "green") if ok else c("✗", "red")
        stamp = c(mmss(now - self.t_start), "faint")
        name = c(pad(desc, 40), "text")
        took = c(pad(fmt_ms(dt * 1000), 9, "r"), "dim")
        bits = []
        if "tl" in res:
            tl = res["tl"]
            bits.append(f"ready in {c(fmt_ms(tl['ready_ms']), self._rcolor(group, tl['ready_ms']), bold=True)}" if tl.get("ready_ms")
                        else c("never became ready", "red"))
            if tl.get("spans"):
                big = max(tl["spans"], key=lambda s: s[2] - s[1])
                bits.append(c(f"longest: {big[0]} {fmt_ms(big[2] - big[1])}", "dim"))
        elif res.get("note"):
            bits.append(c(res["note"], "red"))
        elif res.get("settle_ms") is not None:
            metric = res["paint_ms"] if (info and info[1] == "input" and res.get("paint_ms") is not None) else res["settle_ms"]
            label = "feedback" if metric is res.get("paint_ms") else "done"
            bits.append(f"{c(label, 'dim')} {c(fmt_ms(metric), self._rcolor(group, metric), bold=True)}")
            if res.get("paint_ms") is not None and metric is not res["paint_ms"]:
                bits.append(c(f"first paint {fmt_ms(res['paint_ms'])}", "dim"))
            if res.get("frames") is not None:
                bits.append(c(f"{res['frames']} fr · {fmt_bytes(res.get('bytes'))}", "dim"))
            if res.get("went") is False and group.startswith("nav"):
                bits.append(c("no page change", "yellow"))
        if not res.get("alive", True) and group != "shutdown":
            bits.append(c("app exited", "red"))
        if res.get("settle_ms") and (self.slowest is None or res["settle_ms"] > self.slowest[1]) and info and info[1] != "idle":
            if group not in ("startup.cold", "shutdown"):
                self.slowest = (desc, res["settle_ms"])
        return f"  {glyph} {stamp}  {name}{took}   " + "  ".join(bits)

    def _rcolor(self, group, v):
        info = GROUP_INFO.get(group)
        return term.RATING_COLOR[rate(v, info[2])] if info else "text"

    # ── drawing ──────────────────────────────────────────────────────────────
    def _print(self, line):
        with self.lock:
            self._log(line)

    def _log(self, line):
        if self.tty:
            self._clear_footer()
            self.out.write(line + "\n")
            self._draw_footer()
        else:
            self.out.write(term.ANSI_RE.sub("", line) + "\n")
        self.out.flush()

    def _clear_footer(self):
        if self.tty and self.drawn:
            self.out.write(f"\x1b[{self.FOOT - 1}A\r\x1b[J")
            self.drawn = False

    def _loop(self):
        while not self.stop.wait(0.1):
            with self.lock:
                if self.tracer is not None:
                    now = time.time()
                    self.trace_samples.append((now, self.tracer.lines))
                    self.trace_samples = [s for s in self.trace_samples if now - s[0] < 6]
                self._clear_footer()
                self._draw_footer()
                self.out.flush()

    def _draw_footer(self):
        if not self.tty:
            return
        w = term.width()
        self.frame += 1
        now = time.time()
        spin = c(SPIN[self.frame % len(SPIN)], "cyan", bold=True)
        if self.cur:
            running = now - self.cur_t0
            l1 = f"  {spin} {c(self.cur, 'white', bold=True)}  {c(f'{running:5.1f} s', 'yellow')}"
        else:
            l1 = f"  {spin} {c('working…', 'dim')}"
        frac = min(1.0, self.done_weight / self.total_weight)
        elapsed = now - self.t_start
        eta = elapsed / frac - elapsed if frac > 0.03 else None
        bw = max(16, min(40, w - 70))
        l2 = (f"  {c(pad(self.phase_label or 'starting', 28), 'dim')} {term.bar(frac, bw, 'cyan')} {c(f'{frac * 100:3.0f}%', 'white', bold=True)}"
              f"  {c(f'step {self.phase_done}/{self.phase_steps}', 'dim')}"
              f"  {c('elapsed ' + eta_str(elapsed), 'dim')}" + (f"  {c('ETA ' + eta_str(eta), 'dim')}" if eta is not None else ""))
        if self.tracer is not None and len(self.trace_samples) > 1:
            (t0, n0), (t1, n1) = self.trace_samples[0], self.trace_samples[-1]
            rate_ = (n1 - n0) / max(t1 - t0, 1e-6)
            l3 = f"  {c('trace', 'purple', bold=True)} {c(f'{self.tracer.lines:,} lines folded', 'text')}  {c(f'{fmt_num(rate_)}/s', 'dim')}"
        else:
            l3 = f"  {c('trace', 'faint')} {c('idle', 'faint')}"
        l4 = (f"  {c('slowest so far', 'dim')} {c(self.slowest[0], 'text')} {c(fmt_ms(self.slowest[1]), 'orange')}"
              if self.slowest else c("  ctrl+c aborts · the app under test runs in a hidden terminal", "faint"))
        self.out.write("\n".join(term.clip(ln, w - 1) for ln in (l1, l2, l3, l4)))
        self.drawn = True
