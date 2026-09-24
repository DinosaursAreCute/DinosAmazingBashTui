### `tui.set_text`

```bash
tui.set_text PANE TEXT
```

Replaces the pane's content like [`tui.output`](/api/core/tui.output.html), but skips the work when `TEXT` equals what it set last time.

**Notes**

- Fork-free. Use it for anything updated from timers or tick functions.
- The cache is per pane and cleared on page change. After changing the pane through another function, the next `tui.set_text` with the old text is skipped; don't mix them on one pane.

**Example**

```bash
refresh() { tui.sys.cpu; tui.set_text cpu "CPU ${TUI_SYS_CPU}%"; }
tui.every 1 refresh
```
