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

## Scenarios for addons and generated pages

`--scenario addons` and `--scenario generated` profile `tui.page.refresh` (`lib/markup/tui_refresh.sh`) on the two demo pages that use it. The pages are not in the nav, so the scenarios reach them through the command palette (`ctrl+p`, then the first letters of the command). Every group has the budget of a page switch: **100 ms**, click to the changed panes on screen.

| scenario | groups | what it tells you |
|---|---|---|
| `addons` | `addons.open`, `addons.apply1`, `addons.apply5` | opening the Addons page, then click on *Apply* until the changed panes are on screen, with one addon and with all five. Every addon is switched off again afterwards. |
| `generated` | `generate.small`, `generate.big` | click on *Generate* until the new cards are on screen: 3 cards x 2 items, then 8 x 6. Shows how the rebuild grows with the number of generated widgets. |

A refresh rebuilds only the panes whose content changed (see the header of `tui_refresh.sh`), so `addons.*` should stay far below the budget and `generate.*` grows with what is generated. After the screen is updated, a quiet background job brings the cached copy of the page up to date; the scenarios wait a second for it (a `setup` step) so it does not land in the next measurement. The probes also wrap `tui.page.refresh`, `tui.job.run`, `_tui_job.finish` and `_tui_job.spinner_draw`.

The steps type into the *Cards:* and *Items:* inputs (click, End, backspace, digits) and click the buttons by their on-screen text, so they depend on the labels in `share/demo/addons.xml` and `share/demo/generated.xml`. If a label changes, change the needles at the top of the scenario steps (`ADDON_BOXES`, `APPLY`, `GENERATE` in `dprof/scenarios.py`). `tests/unit/profiler_scenarios.t.sh` checks that every group has a title, a budget and steps.

## Held arrow key

`--scenario held` models a user holding Up/Down: the terminal's key repeat reaches the app as one write of 30 presses, Down then Up, four times each on the Widgets page list (reached with Tab from the first input) and on the nav bar (focus left there by a nav click). Groups `held.list` and `held.nav`, budget **120 ms** for the whole burst (4 ms per repeat, a quarter of the ~33 ms repeat interval of a held key). The rating uses *done*, key to the last repeat on screen, not the first paint: a held key feels laggy when the tail trails behind. The frames-per-action table shows how many of the 30 repeats were coalesced into one paint.

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
