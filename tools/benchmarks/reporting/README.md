# reporting

The reusable half of the benchmark tools: terminal toolkit, statistics, the default report, a live progress view and a second-window viewer.
Python standard library only. A tool puts `tools/benchmarks` on `sys.path` and imports from `reporting`.

| Module | What it gives |
|---|---|
| `term.py` | colours, bars, sparklines, panels, heat colours; degrades to plain text (`term.init(False)` for no colour) |
| `stats.py` | `pct`, `med`, `stats`, `rate`, `group(...)` (one scorecard row from samples), `compare_groups` (diff against an earlier report) |
| `default_reporter.py` | `render(report, W)`: header, scorecard, one case table per group, optional "where the time goes" panels, diff against the previous run |
| `live.py` | `LiveUI`: a scrolling log of finished steps with a footer for what runs now, phases, ETA, and parallel units (`--jobs`) |
| `watch.py` | `Watch(rows, cols)`: a second terminal window (Hyprland aware) that replays whatever you `write()` to it |

## The results shape

```python
report = {
  "meta": {"title": "…", "commit": "…", "branch": "…", "dirty": False, "scenario": "full", "rounds": 1, "duration_s": 12.0,
           "when": "2026-11-13 20:04", "cols": 150, "rows": 45,          # cols/rows optional
           "cases": 114, "row_label": "renderer", "legend": "…", "method": "…"},
  "latency": [group, ...],        # build each with reporting.stats.group(id, title, samples_ms, budget_ms, details=[...])
  "compare": None,                # reporting.stats.compare_groups(groups, earlier_report)
  "attr": {"functions": [...], "hot_lines": [...]},   # optional: panels "where the time goes" and "hot source lines"
}
detail = {"detail": "case name", "settle": median_ms, "p95": ms, "bytes": n, "forks": n}
```

A group's headline `value` is the median of its samples, rated `good` (within the budget), `ok` (up to twice) or `slow`. `renderers/profile.py` is the
smallest complete user: it builds this shape from a bash harness and prints `default_reporter.render(report)`.
