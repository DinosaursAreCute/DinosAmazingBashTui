"""Pins the CPU frequency governor to 'performance' for the length of a run and restores the previous one afterwards.

Writing scaling_governor needs root, so the change is made by a small shell helper (run through `sudo -n` when this process is not
allowed to write). The helper stays alive blocked on its stdin pipe and restores every CPU when the pipe closes: a normal exit, an
exception, Ctrl-C, SIGTERM and even SIGKILL of this process all close it, so the old governors always come back."""
import glob
import os
import shutil
import subprocess

GLOB = "/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor"
# args: path=original pairs. Sets performance, reports ok/fail, waits for EOF on stdin, restores.
SCRIPT = r'''
restore() { for kv in "$@"; do printf '%s' "${kv#*=}" > "${kv%%=*}" 2>/dev/null; done; }
ok=1
for kv in "$@"; do printf performance > "${kv%%=*}" 2>/dev/null || ok=0; done
if [ $ok = 1 ]; then echo ok; else echo fail; fi
cat > /dev/null
restore "$@"
'''


def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


class Performance:
    def __init__(self):
        self.proc, self.ok, self.changed, self.note = None, False, 0, ""

    def __enter__(self):
        saved = {p: g for p in sorted(glob.glob(GLOB)) if (g := _read(p)) and g != "performance"}
        if not saved:
            self.ok = True  # nothing to do: already performance, or no cpufreq (VM, container)
            return self
        cmd = ["sh", "-c", SCRIPT, "sh", *(f"{p}={g}" for p, g in saved.items())]
        if not all(os.access(p, os.W_OK) for p in saved):
            if not shutil.which("sudo") or subprocess.run(["sudo", "-n", "true"], capture_output=True).returncode:
                self.note = "no write access to the CPU governor and no passwordless sudo"
                return self
            cmd = ["sudo", "-n", *cmd]
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
        self.ok = self.proc.stdout.readline().strip() == "ok"
        self.changed = len(saved)
        if not self.ok:
            self.note = "setting the governor failed on some CPUs"
        return self

    def __exit__(self, *exc):
        if self.proc:
            try:
                self.proc.stdin.close()  # EOF = restore
                self.proc.wait(10)
            except (subprocess.TimeoutExpired, OSError):
                pass
        return False
