### `tui.chart.spark`

```bash
tui.chart.spark VAR [-w N] [-n MIN] [-m MAX] VALUE...
```

Stores one block glyph (`▁` to `█`) per value in `VAR`, scaled between the smallest and the largest value. It does not fork and does not read the renderer file.

**Parameters**

- `-w N`: show only the newest `N` values; fewer values leave the left side blank.
- `-n MIN`, `-m MAX`: a fixed scale instead of the data's.

**Notes**

- Values may have decimals. A value that is not a number counts as `0`. Equal values draw the middle glyph.

**Returns:** `1` without `VAR`.

**Example**

```bash
tui.chart.spark line -w 20 "${samples[@]}"
tui.set_label lbl_trend "$line"
```
