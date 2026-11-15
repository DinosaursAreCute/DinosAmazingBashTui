### `tui.data.find`

```bash
tui.data.find NAME COL VALUE VAR
```

Stores the id of the first row whose cell `COL` equals `VALUE` in `VAR`: the key for a keyed dataset, else the 0-based index.

**Returns:** `1` when no row matches, or for an unknown dataset or column.

**Example**

```bash
tui.data.find hosts state down first_down && tui.notify "$first_down is down" warn
```
