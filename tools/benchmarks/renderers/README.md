# Renderer profiler

Times every renderer of `lib/terminal_renderer.sh` (box, table, hbar, gauge, sparkline, vbar, linechart, the csv and statistics charts, banner,
tree, columns, badges, list, quote, …) through its `*_string` form, on several datasets (size, unicode content) and argument sets (widths, colours,
ranges, styles). Reported per case: median and worst time per call, output bytes and processes started per call, rated against a per-renderer budget.

```
tools/benchmarks/renderers/profile.sh                      ask which scenario (a terminal), else everything
tools/benchmarks/renderers/profile.sh --scenario charts,small
tools/benchmarks/renderers/profile.sh --quick              8 calls per case, no trace
tools/benchmarks/renderers/profile.sh --deep               5 rounds
tools/benchmarks/renderers/profile.sh --trace              also show where the time goes inside the renderers (slow, off by default)
tools/benchmarks/renderers/profile.sh --watch [--wait 1]   show what the renderers draw in a second window (--wait: seconds each stays on screen, default 0)
tools/benchmarks/renderers/profile.sh --help               every option
```

It takes the options of the DABT profiler (`tools/benchmarks/profiler/profile.sh`): `--scenario NAME|N[,..]`, `--list-scenarios`,
`--scenarios FILE|NAME`, `--quick`, `--deep`, `--rounds`, `--size`, `--jobs`, `--watch`, `--wait`, `--trace`, `--set NAME=VALUE`, `--compare`,
`--no-compare`, `--report`, `--out`, `--no-deep-dive`, `--plain`, `--no-color`, `--width`, `--events`. Not applicable here: `--app`, `--cold-trace`,
HTML reports.

**Scenarios** (`scenarios/renderers.py`): `full`, `text`, `tables`, `bars`, `charts`, `stats`, `banner` pick renderers; `small`, `large`, `args`,
`unicode` pick cases by tag across all renderers. Several can be combined (`2,small`).

**Where the time goes** (`--trace`, off by default): the trace runs one xtrace per case, rescales each to that case's measured median (xtrace inflates in-shell time) and averages
over the cases: hot functions and hot source lines, like the profiler's attribution. Forks are counted the same way: every subshell and every program
one call starts, an upper bound.

**Layout**: `harness.sh` measures in bash (one process, deterministic data, private HOME, fixed locale and width); `scenarios/cases.sh` defines the
cases (`rc_case RENDERER DATASET ARGS -- COMMAND`, `rc_budget`); `scenarios/renderers.py` lists the scenarios; `profile.py` runs, reports and saves to
`reports/<timestamp>/` (git-ignored). A new renderer needs cases: `tests/unit/renderer_profiler.t.sh` fails when a public `*_string` renderer has none.
