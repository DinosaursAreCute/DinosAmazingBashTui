### `tui.data.remove`

```bash
tui.data.remove NAME ID...
```

Deletes rows. Ids that do not exist are skipped.

**Notes**

- The row array is rebuilt once for all ids, so removing many rows in one call costs the same as removing one.

**Returns:** `1` for an unknown dataset.

**Example**

```bash
tui.data.remove hosts db1 cache1
```
