### `tui.chart.gauge`

```bash
tui.chart.gauge VAR VALUE [MAX] [-w N]
```

Stores a bar and a percent in `VAR`: `████████░░░░ 67%`. It does not fork and does not read the renderer file.

**Parameters**

- `MAX`: the value that fills the bar. Default 100.
- `-w N`: the bar's width in cells. Default 20.

**Notes**

- A value outside 0 to `MAX` is clamped.

**Returns:** `1` without `VAR`.

**Example**

```bash
tui.chart.gauge bar "$cpu" 100 -w 12
```
