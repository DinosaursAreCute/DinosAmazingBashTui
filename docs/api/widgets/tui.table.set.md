### `tui.table.set`

```bash
tui.table.set [--keep COL] ID HEADER ROW...
```

Replaces the header and all rows, and selects the first row. With `--keep COL` the selection stays on its row instead.

**Parameters**

- `HEADER`, `ROW`: cells separated by `|`, e.g. `"Name|Size"` and `"a.txt|1k"`.
- `--keep COL`: 0-based key column. The row whose cell `COL` equals the selected row's keeps the selection and its position on screen, so a table that refreshes every second does not jump. When that row is gone the selected index stays, clamped to the new rows.

**Notes**

- Each column is as wide as its widest cell; when the table is too wide, the widest columns shrink first (to at least 3). A cell cannot contain `|`.
- Without `--keep` the scroll position resets to the top.

**Example**

```bash
tui.table.set --keep 0 procs "PID|Command" "${rows[@]}"   # column 0 (PID) identifies a row
```
