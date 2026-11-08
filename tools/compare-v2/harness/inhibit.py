"""Keeps the machine awake for the length of a run: a sleeping machine or a dimming display skews timings and can stall a run outright.

Uses a systemd-logind inhibitor lock (what screen savers, idle daemons such as hypridle and the sleep targets all honour). The lock
is held by a helper that exits when this process does, so even a killed run releases it."""
import os
import shutil
import subprocess


class KeepAwake:
    def __init__(self, why):
        self.why, self.proc, self.ok = why, None, False

    def __enter__(self):
        if shutil.which("systemd-inhibit") and shutil.which("tail"):
            self.proc = subprocess.Popen(
                ["systemd-inhibit", "--what=idle:sleep", "--who=compare-v2", f"--why={self.why}", "--mode=block",
                 "tail", f"--pid={os.getpid()}", "-f", "/dev/null"],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            try:
                self.proc.wait(0.3)  # still running after a moment = the lock is held; exited = it was refused
            except subprocess.TimeoutExpired:
                self.ok = True
        return self

    def __exit__(self, *exc):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        return False
