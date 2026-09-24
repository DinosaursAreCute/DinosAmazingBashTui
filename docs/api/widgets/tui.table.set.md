### `tui.table.set`

```bash
tui.table.set ID HEADER ROW...
```

Replaces the header and all rows, and selects the first row.

**Parameters**

- `HEADER`, `ROW`: cells separated by `|`, e.g. `"Name|Size"` and `"a.txt|1k"`.

**Notes**

- Each column is as wide as its widest cell; when the table is too wide, the widest columns shrink first (to at least 3). A cell cannot contain `|`.
