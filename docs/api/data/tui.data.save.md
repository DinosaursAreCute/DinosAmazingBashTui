### `tui.data.save`

```bash
tui.data.save NAME
```

Writes the rows of a dataset to `$TUI_HOME/state/data/NAME`: one row per line, with `\` and newlines escaped, through a temporary file that is moved into place.

**Notes**

- Datasets of scope `disk` are written by themselves when the page is left and when the app exits.

**Returns:** `1` for an unknown dataset or without a `TUI_HOME`.
