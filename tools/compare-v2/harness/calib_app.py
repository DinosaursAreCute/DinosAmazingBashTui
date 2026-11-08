#!/usr/bin/env python3
"""Reference app for `compare.py selftest`: answers each key after a KNOWN delay, so the harness's own bias and jitter can be measured.
  0,1,2,3 -> redraw after 0, 5, 20, 100 ms
  4       -> synchronized-update frame written in two halves 30 ms apart (must count as ONE paint, visible only at the end)
  5       -> two separate frames 30 ms apart (two paints)
  q       -> quit"""
import os
import sys
import termios
import time
import tty

DELAY = {b"0": 0, b"1": 0.005, b"2": 0.020, b"3": 0.100}
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
tty.setraw(fd)
w = lambda s: os.write(1, s.encode())
w("\x1b[?1049h\x1b[2J\x1b[Hcalib ready")
n = 0
try:
    while True:
        k = os.read(fd, 1)
        if k in DELAY:
            time.sleep(DELAY[k])
            n += 1
            w(f"\x1b[2J\x1b[Hdone {n}")
        elif k == b"4":
            n += 1
            w(f"\x1b[?2026h\x1b[2J\x1b[Hhalf {n}")
            time.sleep(0.030)
            w(f"\x1b[2J\x1b[Hfull {n}\x1b[?2026l")
        elif k == b"5":
            n += 1
            w(f"\x1b[2J\x1b[Hfirst {n}")
            time.sleep(0.030)
            w(f"\x1b[2J\x1b[Hsecond {n}")
        elif k in (b"q", b""):
            break
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
