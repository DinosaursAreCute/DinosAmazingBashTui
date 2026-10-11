### `tui.md.table_overflow`

```bash
tui.md.table_overflow wrap|truncate
```

Chooses what happens to a table cell that is wider than its column.

**Parameters**

- `wrap|truncate`: `wrap` makes the row taller, `truncate` cuts the cell with an ellipsis.

**Returns:** `1` for another name.

**Notes**

- Persisted as `md.table_overflow` in the config.

**Example**

```bash
tui.md.table_overflow truncate
```
