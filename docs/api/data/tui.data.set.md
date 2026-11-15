### `tui.data.set`

```bash
tui.data.set NAME ID COL VALUE
```

Changes one cell of a row.

**Parameters**

- `ID`: the key of the row for a keyed dataset, else its 0-based index.
- `COL`: a 0-based column index or a name from `--cols`.

**Returns:** `1` for an unknown dataset, row or column.

**Example**

```bash
tui.data.set hosts db1 state up
```
