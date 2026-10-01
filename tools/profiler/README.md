# DABT profiler

End-to-end profiler: it runs the **real app** and answers *how fast does it feel*, *where does the time go* and
*who hands work to whom* in one report.

```
tools/profiler/profile.sh               # standard run, ~3 min
tools/profiler/profile.sh --quick       # ~1.5 min
tools/profiler/profile.sh --deep        # 5 rounds + traced cold start, ~10 min
tools/profiler/profile.sh --report tools/profiler/reports/latest    # re-render a saved run
tools/profiler/profile.sh --help
```

Needs bash >= 5 and python3 >= 3.8 (standard library only, nothing to install). The profiler is a dev tool and
may use Python; the DABT runtime stays pure bash.

## What it does

1. **Latency rounds (untraced).** Starts the demo in a hidden pseudo-terminal and plays a scripted user session:
   cold start, warm start, every page (first visit, revisit, and once by key with alt+1…0), Tab/Shift+Tab, mouse hover and click, wheel and
   PgDn scrolling, command palette, three resizes, 3 s idle, quit. Timing comes from probes that
   `probe_shim.sh` wraps around ~18 coarse functions (key/mouse handlers, `tui.goto`, `tui.render`, `_tui._flush`,
   startup phases). Output volume is counted per frame.
2. **Attribution trace.** The same session again with `set -x` and a PS4 that prints
   `epoch | pid | file:line | call stack`. `dprof/trace.py` folds the ~1M lines into per-scenario call stacks while
   the app runs (nothing large is written to disk). Wall time between trace lines is split into in-shell work,
   external programs, process creation and waiting. In-shell time is rescaled per scenario so that it matches
   the untraced busy time; programs and forks are real time and stay as measured.
   `--scenario floor` replays warm switches between the three lightest pages (home, layout, case study; one priming lap, ten
   measured laps) so the trace shows what a page switch costs when no page code runs. For `tui.goto`, `tui.cache.replay`,
   `tui.render` and their neighbours (`FOCUS_ROOTS` in `dprof/scenarios.py`) the report lists, per switch and unpruned, the callee
   the time went into, the functions that ran the commands and the hottest source lines below them: the "Page-switch floor"
   section of the deep dive and of `report.html`.
3. **Report.** Terminal overview first (verdict tiles, latency scorecard against perceived-instant budgets,
   layer heat-matrix, layer-to-layer flow, findings), then the deep dive (startup timeline, flame, hot functions,
   hot source lines, call-graph edges, subprocess and fork sites, slowest actions). `report.html` adds an
   interactive flame graph and sortable tables. The previous run is diffed automatically.

Output: `reports/<timestamp>/{report.json,report.html,report.txt}`, `reports/latest` links the newest run
(`reports/` is git-ignored).

## Reading it

- **Typical** is the median; **done** is key-to-last-frame, **feedback** is key-to-first-painted-frame.
- **Layers** group functions by source file, and by name inside the mixed files (`tui.sh`, `terminal_renderer.sh`).
  Edit `FILE_LAYER` / `FUNC_RULES` in `dprof/analyze.py` if a function lands in the wrong layer.
- **Subprocesses** is the layer for forks (`⟨fork⟩`) and external programs (`⟨awk⟩` ...); the fork table names
  the function that creates them.
- Budgets live in `GROUP_INFO` in `dprof/scenarios.py`; the script itself is `interaction_steps` there.

## Layout

| file | role |
|---|---|
| `profile.sh` | entry: checks bash/python, starts `profile.py` |
| `profile.py` | phases, options, saving and printing reports |
| `probe_shim.sh` | stands in for `lib/tui.sh` inside the profiled app; installs the probes and xtrace |
| `dprof/session.py` | pty session: input, settle detection, per-action metrics |
| `dprof/scenarios.py` | the scripted user session and the budgets |
| `dprof/trace.py` | streaming xtrace aggregator |
| `dprof/analyze.py`, `insights.py` | layers, calibration, call-graph tables, findings |
| `dprof/live.py` | live progress (scrolling log with per-step timings + in-place footer) |
| `dprof/report_term.py`, `report_html.py`, `term.py` | renderers |

## Limits

- The app runs at `--size` (default 150x45); the demo needs at least ~111 columns to show its nav pane.
- Clicks avoid the nav column (its last row is Quit). An app that exits early is reported as a warning.
- xtrace makes bash roughly 3x slower; the calibration corrects the totals but not the relative cost of
  individual lines (cheap builtins are inflated more than forks).

## Documentation site page

`site_export.py` turns saved reports into the interactive page `docs/design/performance-explorer.html` (template in `site/explorer.template.html`, colours from the site's CSS variables so it follows the DABT brand and the light/dark toggle). The revisions and the report each one uses are listed at the top of the script; add a line there after a new optimisation and run `python3 tools/profiler/site_export.py`. Reports live in the git-ignored `reports/` folder, so the page is regenerated on a machine that has them and the result committed.
