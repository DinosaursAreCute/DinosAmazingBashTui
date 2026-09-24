### `tui.hist.get`

```bash
tui.hist.get NAME
```

Prints a series, oldest first.

**Output:** values separated by spaces, no trailing newline. Charts such as `linechart` expect commas: `v=$(tui.hist.get cpu); linechart "cpu:${v// /,}"`.
