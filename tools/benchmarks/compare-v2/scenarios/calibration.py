"""Measures the harness itself against an app with known delays. Step names carry the nominal delay: delay.<ms>ms."""
from harness.scenario import scenario

N = 12


@scenario("calibration", ready="calib ready", title="Harness self-check against known delays", apps=("calib",))
def calibration(c):
    for i in range(N):
        c.step("delay.0ms", b"0", f"done {i + 1}")
    for i in range(N):
        c.step("delay.5ms", b"1", f"done {N + i + 1}")
    for i in range(N):
        c.step("delay.20ms", b"2", f"done {2 * N + i + 1}")
    for i in range(N):
        c.step("delay.100ms", b"3", f"done {3 * N + i + 1}")
    for i in range(N):  # frame is invisible until the sync block closes: ready must be ~30 ms, paints exactly 1
        c.step("sync.30ms", b"4", f"full {3 * N + N + i + 1}")
    for i in range(N):  # three keys 20 ms apart, each answered after 5 ms: timed from the LAST key, so ~5 ms (not 45)
        c.step("multi.5ms", [b"1", b"1", b"1"], f"done {5 * N + 3 * (i + 1)}", gap_ms=20)
