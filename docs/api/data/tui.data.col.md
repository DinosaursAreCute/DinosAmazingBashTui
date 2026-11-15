### `tui.data.col`

```bash
tui.data.col NAME COL ARRAY [--last N]
```

Fills the array `ARRAY` with one column, oldest first. With `--last N` only the newest `N` values.

**Returns:** `1` for an unknown dataset or column.

**Example**

```bash
tui.data.col latency ms values --last 24
tui.chart.spark line "${values[@]}"
```
