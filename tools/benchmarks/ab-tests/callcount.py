#!/usr/bin/env python3
"""Exact count of the function calls a headless command makes, by name and call depth, with a live view while it runs.

  callcount.py [--name N] [--paths lib,plugins] [--no-baseline] [--keep] -- COMMAND [ARGS...]

How: the repo is copied to a temp dir and every function definition under --paths (default lib) gets a counter call as its first statement
(`f() { _cc; ...`); COMMAND runs inside the copy (so `tools/bench/hit.sh` means the copy's script). `_cc` writes the call stack to a pipe the runner
reads, so calls made in subshells and child shells count too, and no state is lost. A file that does not pass `bash -n` after the edit is left as it was.
Before that the command runs once untouched, to know how long it really takes (the counting run is slower; --no-baseline skips it).

Live: the shared LiveUI footer shows the calls so far, calls per second, deepest stack and the hottest function; the scrolling log gets a line every 5 s.
The command needs no terminal: its output goes to out.log (a TUI app needs the profiler, whose trace pass records depths too).

Marks: a script under test can split the count into sections with `callcount.mark NAME` (exported function; a no-op outside this runner: guard it
with `declare -F callcount.mark >/dev/null &&`).

Result: callcounts/<UTC>_<name>/{calls.tsv, meta.txt, out.log}, then the cross-reference with the ab-tests cost model (callmodel.py) when a calls-depth run exists.
Not counted: functions created by eval, function-like text inside heredocs is edited too (check generated code if a lib file writes functions out), functions outside --paths, builtins and external programs.
"""
import argparse
import collections
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))   # tools/benchmarks: the shared reporting package
sys.path.insert(0, HERE)

import callmodel                                                            # noqa: E402
from reporting import default_reporter as dr, term                          # noqa: E402
from reporting.live import LiveUI                                           # noqa: E402
from reporting.term import c, pad, panel, bar, fmt_ms, fmt_num              # noqa: E402

REPO = callmodel.REPO
OUT = os.path.join(HERE, "callcounts")
NOT_A_CALL = ("main", "source", "_cc", "callcount.mark")
SKIP_COPY = shutil.ignore_patterns(".git", "logs", "dist", "screenshots", "reports", "release-notes", "__pycache__", "runs", "callcounts")
DEF = re.compile(r"^((?:function\s+[A-Za-z_][\w.:@-]*\s*(?:\(\))?|[A-Za-z_][\w.:@-]*\s*\(\))\s*\{)(.*)$")

PRELUDE = r"""# sourced through BASH_ENV by every bash the command starts (subshells inherit the functions by forking)
_cc() { local IFS=' '; printf '%s\n' "${FUNCNAME[*]:1}" 2>/dev/null >&"$CC_FD"; }
callcount.mark() { printf '#%s\n' "$1" 2>/dev/null >&"$CC_FD"; }
"""


def instrument(text):
    """The shell source with `_cc;` as the first statement of every column-0 function definition. Returns (new text, number of functions)."""
    out, n = [], 0
    for line in text.split("\n"):
        m = DEF.match(line)
        if m:   # one-liners `f() { ...; }` and `f() {` plus a body on the next lines both end up as `f() { _cc; ...`
            line = f"{m.group(1)} _cc;{m.group(2)}"
            n += 1
        out.append(line)
    return "\n".join(out), n


def instrument_tree(root, paths):
    """Instruments the .sh files under ROOT/PATHS; returns (functions instrumented, files instrumented, files left untouched)."""
    nfn = nfiles = bad = 0
    for sub in paths:
        for d, _, files in os.walk(os.path.join(root, sub)):
            for fn in files:
                if not fn.endswith(".sh"):
                    continue
                p = os.path.join(d, fn)
                with open(p, encoding="utf-8", errors="surrogateescape") as f:
                    text = f.read()
                new, n = instrument(text)
                if not n:
                    continue
                with open(p, "w", encoding="utf-8", errors="surrogateescape") as f:
                    f.write(new)
                if subprocess.run(["bash", "-n", p], capture_output=True).returncode:
                    with open(p, "w", encoding="utf-8", errors="surrogateescape") as f:
                        f.write(text)
                    bad += 1
                else:
                    nfn += n
                    nfiles += 1
    return nfn, nfiles, bad


class Counter:
    """Reads the stack lines from the pipe: {section: {(function, depth): calls}}; the live figures are read by the main thread."""

    def __init__(self, fd):
        self.fd = fd
        self.sections = collections.defaultdict(collections.Counter)
        self.section = "(all)"
        self.total = 0
        self.max_depth = 0
        self.by_fn = collections.Counter()
        self.lock = threading.Lock()
        self.th = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.th.start()

    def _run(self):
        with os.fdopen(self.fd, "rb", buffering=1 << 20) as f:
            for raw in f:
                line = raw.rstrip(b"\n").decode("utf-8", "replace")
                if line.startswith("#"):
                    with self.lock:
                        self.section = line[1:] or "(all)"
                    continue
                names = line.split()
                if not names:
                    continue
                depth = sum(1 for n in names if n not in NOT_A_CALL)
                with self.lock:
                    self.sections[self.section][(names[0], depth)] += 1
                    self.total += 1
                    self.by_fn[names[0]] += 1
                    if depth > self.max_depth:
                        self.max_depth = depth

    def snapshot(self):
        with self.lock:
            top = self.by_fn.most_common(1)
            return self.total, self.max_depth, (top[0] if top else None), self.section


def git_rev():
    try:
        rev = subprocess.run(["git", "-C", REPO, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip() or "no-git"
        dirty = subprocess.run(["git", "-C", REPO, "status", "--porcelain"], capture_output=True, text=True).stdout.strip()
        return rev + ("+dirty" if dirty else "")
    except OSError:
        return "no-git"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", default=None, help="run name (default: the command's basename)")
    ap.add_argument("--paths", default="lib", help="comma separated dirs of the repo whose functions are counted (default lib)")
    ap.add_argument("--no-baseline", action="store_true", help="skip the untouched run that measures the real duration")
    ap.add_argument("--keep", action="store_true", help="keep the instrumented copy of the repo (its path is printed)")
    ap.add_argument("--plain", action="store_true", help="no live footer")
    ap.add_argument("--no-color", action="store_true")
    ap.add_argument("--model", metavar="RUN", help="calls-depth ab.sh run for the cost model (default: the latest one)")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd[:1] == ["--"] else a.cmd
    if not cmd:
        ap.error("no command: callcount.py [options] -- COMMAND [ARGS...]")
    term.init(False if a.no_color else None)
    first = os.path.join(REPO, cmd[0])
    if os.path.isfile(first) and cmd[0].endswith(".sh") and not os.access(first, os.X_OK):
        cmd = ["bash"] + cmd   # a .sh file without the exec bit: run it with bash
    if shutil.which(cmd[0], path=os.pathsep.join([REPO, os.environ.get("PATH", "")])) is None and not os.path.isfile(first):
        ap.error(f"'{cmd[0]}' is neither a file in the repo nor a program on PATH")
    name = a.name or re.sub(r"\W+", "-", os.path.basename(cmd[0]))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = os.path.join(OUT, f"{stamp}_{name}")
    os.makedirs(run_dir)
    tmp = tempfile.mkdtemp(prefix="dabt-callcount-")
    copy = os.path.join(tmp, "repo")

    phases = ([] if a.no_baseline else [("base", "Baseline run (untouched)", 1, 1)]) + [("prep", "Instrumenting a copy", 1, 1), ("count", "Counting run", 1, 1)]
    ui = LiveUI(phases, tty=False if a.plain else None, hint="starting", show_trace=False)
    ui.begin(["", f" {c('◆', 'cyan', bold=True)} {c('CALL COUNT', 'white', bold=True)}  {c(' '.join(cmd), 'dim')}",
              f" {c('exact calls by name and depth · the counting run is slower than the baseline · output of the command: ' + os.path.relpath(run_dir, HERE) + '/out.log', 'faint')}", ""])
    status = 0
    try:
        baseline_ms = None
        if not a.no_baseline:
            ui.phase("base")
            ui.step_begin("baseline: " + " ".join(cmd))
            t0 = time.time()
            rc = subprocess.run(cmd, cwd=REPO, stdin=subprocess.DEVNULL, stdout=open(os.path.join(run_dir, "baseline.log"), "w"), stderr=subprocess.STDOUT).returncode
            baseline_ms = (time.time() - t0) * 1000
            ui.step_end("baseline run", {"group": "baseline", "ok": rc == 0, "settle_ms": baseline_ms, "extra": [f"exit {rc}"]})

        ui.phase("prep")
        ui.step_begin("copying the repo and instrumenting " + a.paths)
        shutil.copytree(REPO, copy, ignore=SKIP_COPY, symlinks=True)
        nfn, nfiles, bad = instrument_tree(copy, [p for p in a.paths.split(",") if p])
        ui.step_end("instrumented", {"group": "prep", "ok": nfn > 0, "settle_ms": 0.0, "extra": [f"{nfn} functions in {nfiles} files"]})
        if bad:
            ui.warn(f"{bad} file(s) failed `bash -n` after the edit and were left uninstrumented: their functions are not counted")
        if not nfn:
            ui.warn("no function was instrumented: --paths wrong?")
            return 2
        prelude = os.path.join(tmp, "prelude.sh")
        with open(prelude, "w") as f:
            f.write(PRELUDE)

        r, w = os.pipe()
        os.set_inheritable(w, True)
        env = dict(os.environ, BASH_ENV=prelude, CC_FD=str(w))
        ctr = Counter(r)
        ctr.start()
        ui.phase("count")
        ui.step_begin("counting: " + " ".join(cmd))
        t0 = time.time()
        proc = subprocess.Popen(cmd, cwd=copy, env=env, pass_fds=(w,), stdin=subprocess.DEVNULL,
                                stdout=open(os.path.join(run_dir, "out.log"), "w"), stderr=subprocess.STDOUT)
        os.close(w)
        last_note, last_total, last_t = t0, 0, t0
        while proc.poll() is None:
            time.sleep(0.2)
            now = time.time()
            total, deepest, top, sec = ctr.snapshot()
            rate = (total - last_total) / max(now - last_t, 1e-6)
            last_total, last_t = total, now
            hot = f" · hottest {top[0]} {top[1] / max(total, 1) * 100:.0f}%" if top else ""
            ui.hint = (f"calls {total:,} · {fmt_num(rate)}/s · deepest stack {deepest}{hot}" + (f" · section {sec}" if sec != "(all)" else "")
                       + (f" · baseline took {fmt_ms(baseline_ms)}" if baseline_ms else ""))
            if now - last_note >= 5:
                ui.note(f"{now - t0:5.0f} s   {total:,} calls   {fmt_num(rate)}/s   deepest {deepest}")
                last_note = now
        counted_ms = (time.time() - t0) * 1000
        ctr.th.join(5)
        status = proc.returncode
        total, deepest, _, _ = ctr.snapshot()
        ui.step_end("counting run", {"group": "count", "ok": status == 0, "settle_ms": counted_ms, "extra": [f"{total:,} calls · deepest {deepest} · exit {status}"]})
        if status:
            ui.warn(f"the command exited {status}: see out.log")
    finally:
        ui.finish()
        if a.keep:
            print(f"instrumented copy kept: {copy}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)

    with open(os.path.join(run_dir, "calls.tsv"), "w", encoding="utf-8") as f:
        for sec, cnt in ctr.sections.items():
            for (fn, depth), n in sorted(cnt.items(), key=lambda kv: -kv[1]):
                f.write(f"{sec}\t{fn}\t{depth}\t{n}\n")
    meta = {"name": name, "stamp": stamp, "cmd": " ".join(cmd), "git": git_rev(), "paths": a.paths, "functions_instrumented": nfn,
            "baseline_ms": "" if baseline_ms is None else f"{baseline_ms:.1f}", "counted_ms": f"{counted_ms:.1f}", "exit": status,
            "calls": total, "max_depth": deepest, "host": os.uname().nodename, "kernel": f"{os.uname().sysname} {os.uname().release}"}
    with open(os.path.join(run_dir, "meta.txt"), "w", encoding="utf-8") as f:
        f.write("".join(f"{k}\t{v}\n" for k, v in meta.items()))

    calls, m = callmodel.load_calls(run_dir)
    depth_run = a.model or callmodel.latest_run("call-depth")
    if depth_run:
        variants = callmodel.latest_run("call-variants")
        per_local, per_arg = callmodel.variant_costs(variants)
        text = callmodel.render(calls, m, callmodel.depth_curve(depth_run), per_local, per_arg, 2.0, callmodel.static_locals(),
                                depth_run=depth_run, variants_run=variants or "")
        print("\n".join(text))
        term.set_color(False)
        with open(os.path.join(run_dir, "model.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(callmodel.render(calls, m, callmodel.depth_curve(depth_run), per_local, per_arg, 2.0, callmodel.static_locals(),
                                               depth_run=depth_run, variants_run=variants or "")) + "\n")
    else:
        print(f"\n{total:,} calls, deepest stack {deepest}. No price list yet: run `ab.sh run scenarios/calls-all.sh`, then `callmodel.py {run_dir}`.")
    print(f"\nsaved: {run_dir}")
    return status


if __name__ == "__main__":
    sys.exit(main())
