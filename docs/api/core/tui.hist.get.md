### `tui.hist.get`

```bash
tui.hist.get NAME [VAR]
```

Prints a series, oldest first. With `VAR` the series is stored in that variable instead, which costs no subshell.

**Output:** values separated by spaces, no trailing newline. Charts such as `linechart` expect commas: `v=$(tui.hist.get cpu); linechart "cpu:${v// /,}"`.
