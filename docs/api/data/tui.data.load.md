### `tui.data.load`

```bash
tui.data.load NAME
```

Reads the disk copy of a dataset, replacing its rows. `tui.data.new` with `--scope disk` does this itself.

**Returns:** `1` for an unknown dataset, without a `TUI_HOME`, or when there is no copy (the rows stay as they are).
