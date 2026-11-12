### `tui.perf.mean_render_ms`

```bash
tui.perf.mean_render_ms SECONDS [VAR]
```

Prints the mean frame render time in milliseconds over the last `SECONDS`.

With `VAR` the value is stored in that variable instead of printed, so the call needs no subshell.

**Output:** an integer, or nothing when tracking is off or no frame fell in the window.

**Notes**

- Tracking is off by default. Set `_TUI_PERF_TRACKING=1` to turn it on (used by the debug page and `tools/debug/`).
