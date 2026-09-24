### `tui.ansi`

```bash
tui.ansi ID [STATE]
```

Prints the ANSI escape prefix of a widget or pane style (no reset). A state without rules falls back to `normal`.

**Notes**

- Runs in a subshell when used as `$(tui.ansi ...)`; in loops prefer [`tui.style.sgr`](/api/style/tui.style.sgr.html).
