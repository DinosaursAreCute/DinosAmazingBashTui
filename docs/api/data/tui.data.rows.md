### `tui.data.rows`

```bash
tui.data.rows NAME ARRAY [--last N]
```

Fills the array `ARRAY` with the rows, oldest first. With `--last N` only the newest `N` rows.

**Returns:** `1` for an unknown dataset.

**Example**

```bash
tui.data.rows log recent --last 10
tui.table.set tbl "Time|Text" "${recent[@]}"
```
