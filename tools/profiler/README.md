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

## Units, machine and resources

Every run builds one **warmed template** first (a cold start fills the cache, a second start proves it is warm; both are measured as `startup.cold` / `startup.warm`). Each **unit** (`UNIT_GROUPS` in `dprof/scenarios.py`: nav, floor, input, scroll, one per held key, palette, theme, compose, workspace, state, scrollform, resize, idle, shutdown) then runs on its own: a private copy of the template HOME, a fresh app that lands on the default page, `setup` steps (navigate to the page, put it in its start state; timed and shown in the report's *Setup* panel, but never counted in a measured group), then the measured steps. Units share nothing, so what one does to the app (a dialog left open, a setting changed) cannot reach another, and they can run side by side: `--jobs N`. Parallel runs compete for the CPU, so the report says so and the timings are only comparable with runs made with the same `--jobs`. The traced pass always runs one unit at a time.

The report names the machine, specs only: CPU model, threads and cores, max MHz and governor, RAM, distro, kernel, virtual or bare metal, filesystem of the temp dir, bash and Python versions, plus a short id (a hash of those specs) to tell two machines apart. No host name, user name, path or address is read. While the run goes, a sampler reads `/proc` every 250 ms; per unit the report shows wall time, app CPU and memory, machine CPU, CPU used by **other work** (a finding when it is 0.5 core or more on a single-job run: the timings are inflated), mean frequency and peak memory use. Linux only; elsewhere those fields are empty.

## Explorer

`tools/profiler/explorer/index.html` is an offline explorer for every run in `reports/`: open the file, nothing to install or serve. `profile.py` refreshes its data after each run (`explore.py` writes `reports/index.js` and a `report.js` beside each `report.json`, only for new or changed runs); `tools/profiler/explorer.sh` does the same on demand and opens the page. If the data files are missing, the page asks for the reports folder (or dropped `report.json` files) and reads them directly.

* **Overview** (first page): the progression of every group of every scenario on one log-scale chart (as multiples of budget, % of the first run, or absolute ms), filterable by machine, mode and window, with a legend to hide or isolate groups and one tile per group: latest value, change against the previous and first run, and a sparkline. Groups that no longer exist are left out unless asked for.
* **Runs:** all runs in one sortable, filterable table (machine, branch, mode, scenario); open one, or tick several to compare.
* **One run:** summary and scorecard, latency with every statistic, samples, per-step timelines, frame sources, panes and spans; startup phases; setup; machine and resources; functions, layers, call edges, layer flow, hot lines, processes; zoomable flame graph; calibration; findings; the raw JSON as a tree.
* **Compare (2 or more runs):** latency, startup phases, functions, layers, setup and resources side by side with the change against the first run, distributions per group, and a context table that marks what differs between runs (including the machine).

## Scenario for the Compose page

`--scenario compose` profiles `tui.page.refresh` (`lib/markup/tui_refresh.sh`) on the **Compose** demo page (`share/demo/compose.xml`, `compose_callbacks.sh`; tabs Board, Conditionals, Addons; `alt+-`). The page is not in the nav's first ten pages, so the scenario opens it through the command palette (`ctrl+p`, then the first letters of its command). Every change on it is an addon file plus a refresh, so every group has the budget of a page switch: **100 ms**, click to the changed panes on screen (the page itself 150 ms).

| group | what it tells you |
|---|---|
| `compose.open` | opening the page from the palette |
| `compose.add` | click *Add task*: a new card from the `task` template, with its `<if>` conditionals |
| `compose.tab` | switch to the Conditionals tab, to Addons and back to Board: the whole view pane tree is swapped |
| `compose.cond` | click *Cycle environment*: only the conditional panel changes |
| `compose.addons` | tick the five example addons and click *Apply and rebuild* |

After the screen is updated, a quiet background job brings the cached copy of the page up to date; the scenario waits a second for it (a `setup` step) so it does not land in the next measurement. The board and every addon are put back as found. The probes also wrap `tui.page.refresh`, `tui.job.run`, `_tui_job.finish` and `_tui_job.spinner_draw`.

The steps type into the *Title:* input and click buttons and tabs by their on-screen text, so they depend on the labels in `share/demo/compose.xml`. If a label changes, change the needles at the top of the scenario steps (`ADD_TASK`, `REMOVE_TASK`, `CYCLE_ENV`, `ADDON_BOXES`, `APPLY` in `dprof/scenarios.py`). `tests/unit/profiler_scenarios.t.sh` checks that every group has a title, a budget and steps.

## Scenarios for the v2 pages

`--scenario workspace`, `--scenario state` and `--scenario scrollform` (all part of `full`, about 15 s each) profile the v2 behaviour. Each is a unit of its own (see `UNIT_GROUPS`). Steps that need a spot on screen use the `pointer` step kind (`session.py`): one mouse event (`_pointer` in `scenarios.py`: move, press, drag, release, wheel) placed relative to the on-screen text of a pane title, so the coordinates follow the terminal size and the divider the pointer drags.

| group | what it tells you |
|---|---|
| `workspace.open` | first visit of the Workspace page (fused log panes, dividers, collapsible Services pane) |
| `workspace.hover_handle` | the pointer moves onto and off a divider: the hover repaint of two border segments (30 ms) |
| `workspace.drag` | every step of a drag: press, 12 moves, release, for the logs/events divider (vertical) and the services/logs divider (horizontal); the median is one pointer step |
| `workspace.resize_key` | `alt+r`, five arrow presses, `shift+right`, Enter |
| `workspace.collapse_click` | click the collapse button (the `◀` on the Services border) and the expand button (`▶`) |
| `workspace.collapse_key` | `alt+c` twice (collapse, expand) |
| `workspace.tick` | 3 s idle while the log streams: the cost of the page's `tui.every` refreshes (kind idle, not rated) |
| `state.plain_goto`, `state.save_restore` | the same round trip, once between two pages that keep nothing (Monitor, Components) and once away from and back to Widgets with `keep_value` on its *User:* input (`share/demo/widgets.xml`); the difference is the cost of the page-state store. The restore step expects the typed value back on screen |
| `state.reset` | `alt+shift+r` on the Workspace page after a keyboard resize and a collapse |
| `scrollform.tab` | Tab through every field of the form on the Scrolling page (`scroll_into_view`) |
| `scrollform.wheel`, `scrollform.pgdn` | wheel over a widget of the form, Page Down |
| `scrollform.click` | click fields after the form has scrolled |

The steps find panes by title (`Events`, `Logs`), the collapse button by its glyph and fields by their label; if the demo changes them, edit the needles above `_workspace_steps` in `dprof/scenarios.py`. A step whose needle is not on screen is reported as failed and its group is not a measurement. The `micro-benches` for the same code (`resize_drag_step`, `collapse_toggle`, `hit_with_handles`, `hover_zone_move`, `store_save_restore`) are in `tools/bench/run.sh`.

## Held keys

`--scenario held` models a user holding a key at the real repeat rate (33 ms between presses, holds of 0.1 to 1 s). Groups `held.nav`, `held.list`, `held.table`, `held.type`, `held.cursor`, `held.tab`, `held.scroll`, `held.page` (kind `held`), budget **50 ms**. Per press the lag is the time from the key sent to the first output the terminal receives; the report also shows the render cadence. A group is rated on its worst press. A press that paints nothing is paired with the next unrelated frame, so a group whose presses often paint nothing over-reports (`held.scroll` lands on a textarea).

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
