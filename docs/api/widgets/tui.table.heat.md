### `tui.table.heat`

```bash
tui.table.heat ID COL WARN HOT
```

Colours the numeric cells of a column by size: the `table_warn` class from `WARN` up, `table_hot` from `HOT` up.

**Parameters**

- `COL`: 0-based column. Cells that do not start with a whole number are left alone.
- `WARN`, `HOT`: whole-number thresholds. Without a theme rule the colours are yellow and red.

**Notes**

- The selected row keeps its selection colours.
- A table with a heat column and columns too wide for the pane (cut short) is drawn without heat.

**Example**

```bash
tui.table.heat procs 4 50 80   # CPU% column: yellow from 50, red from 80
```
