### `tui.perf.report`

```bash
tui.perf.report
```

Prints one line per tracked span (`span<TAB>name<TAB>mean_us<TAB>p95_us<TAB>count`) and one line per counter (`counter<TAB>name<TAB>total`).

**Notes**

- Tracking is off by default. Set `_TUI_PERF_TRACKING=1` to turn it on.
- `TUI_PERF_LOG=FILE` dumps this same report to `FILE` once, at exit.
