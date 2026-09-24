### `tui.palette.open`

```bash
tui.palette.open [QUERY]
```

Opens the command palette, optionally with the search prefilled. Bound to `ctrl+p` and `:` by default.

**Notes**

- Does nothing before the app runs.
- Keys inside: type to filter (every word must match), Up/Down or `ctrl+p`/`ctrl+n`, PgUp/PgDn, Enter runs, Esc closes, `ctrl+u` clears. Click a row to run it.
- Shows `TUI_PALETTE_ROWS` rows (default 10).
