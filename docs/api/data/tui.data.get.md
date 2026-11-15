### `tui.data.get`

```bash
tui.data.get NAME ID VAR
```

Stores a row, its cells joined by `|`, in `VAR`.

**Returns:** `1` for an unknown dataset or row.

**Example**

```bash
tui.data.get hosts web1 row
IFS='|' read -ra cells <<<"$row"
```
