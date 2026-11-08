# compare-v2

Black-box benchmarking of terminal apps (DABT vs Textual, extendable to any app that draws on a tty).
Nothing inside the apps is instrumented: each runs in a pty, gets scripted input, and everything is derived from its output stream.

```
./compare.py run                       # scenario "session", dabt vs textual, 10 rounds
./compare.py run quick --rounds 3 --warmup 0
./compare.py run session --apps dabt,dabt-themed,textual   # first app = baseline
./compare.py report reports/<run>/results.json              # re-render without re-running
./compare.py list
```
While it runs: every finished step is logged with its measured values (and the median of the earlier rounds for that step), under a
footer with the running step, progress and ETA. `--reporter live|plain|none` picks the display (live degrades to plain without a tty),
`--events FILE` adds JSON-lines progress, `--watch` shows the app in a second window of the test size (shared viewer from
`tools/profiler/dprof/watch.py`; watched runs are flagged and their timings are not comparable).
Reporters live in `harness/reporter.py` behind a small hook interface (`run_start`, `round_start`, `step_begin`, `step_end`, `round_end`, `warn`, `run_end`);
subclass `Reporter` and add it to `make()` to switch to another display.

Output per run in `reports/<stamp>-<scenario>/`: `results.json` (every sample), `report.txt`, `report.html`.
Needs `rich` + `pyte` (it re-execs into `$COMPARE_VENV`, default `~/.cache/dabt-compare-venv`, where `pip install rich pyte textual` is enough).
Run it while the machine is otherwise idle; the report warns about governor, load and busy cores.

## Extending

Scenarios and apps are plain Python files; drop them in `scenarios/` / `apps/` or any directory passed as `--plugins DIR`.

```python
# scenarios/my_scenario.py
from harness.scenario import scenario
from harness.keys import click, DOWN, chars
from harness.expect import text, regex, where

@scenario("my-scenario", ready="Welcome", title="what it measures")
def my_scenario(c):
    c.step("nav.settings", click(5, 3), expect="Settings")             # time from input to the screen showing the text
    c.step("scroll.burst", DOWN * 10, expect=regex(r"Item 1\d"))
    c.step("type.word", chars("hello"), gap_ms=30, expect="hello")    # list of inputs, written 30 ms apart
    c.step("resize", resize=(30, 90))                                  # no expect: measures until the screen settles
    for i in range(20):                                                # same name = more samples of one measurement
        c.step("key.down", DOWN, where(lambda v: f"row {i}" in v.text))
    c.idle("idle.3s", 3)
    c.memory("memory")
    c.snapshot("final screen")                                         # stored in the report, to compare what both drew
```
Input must arrive at human speed: send a held key as a list with `gap_ms=33`, typing with `gap_ms=60`, wheel notches `gap_ms=25`. Never write many keys in one `bytes` (that is a backlog no person can produce).

`ready` may be `{app_name: expect}` when apps differ. `c.app` is the App under test. `c.wait_for(expect)` / `c.pause(s)` are untimed.

```python
# apps/my_app.py
from harness.apps import App, register
register(App("myapp", "My App", lambda home: ["/path/to/bin", "--flag"], color="green",
             background_done="cache ready", version=lambda: "v1.2"))
```
Input helpers: `harness/keys.py` (click, move, wheel, paste, ctrl, arrows, ...). Predicates: `harness/expect.py` (text, absent, regex, row, where, combinable with `&`, `|`, `~`).

## Layout
`harness/term.py` pty + reader thread + emulator · `measure.py` steps → metrics · `probe.py` /proc CPU/memory · `stats.py` bootstrap & verdicts ·
`runner.py` rounds/interleaving · `reporter.py` live/plain/JSON progress hooks · `watch.py` --watch · `report_term.py`, `report_html.py` · `sysinfo.py` environment checks.
