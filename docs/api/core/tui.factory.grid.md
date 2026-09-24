### `tui.factory.grid`

```bash
tui.factory.grid NS PARENT COUNT [COLS] [FIT] [ROW_WEIGHTS] [COL_WEIGHTS]
```

Builds a grid of `COUNT` cells with generated pane ids, for layouts whose size is only known at runtime.

**Parameters**

- `COUNT`: number of cells.
- `COLS`: columns. Omitted: near-square.
- `FIT`, `ROW_WEIGHTS`, `COL_WEIGHTS`: as in [`tui.grid`](/api/core/tui.grid.html).

**Sets:** `_TUI_FACTORY_GRID_CELLS` (array of cell ids, in order).

**Example**

```bash
tui.factory.clear tiles
tui.factory.grid tiles board "${#items[@]}" 4
for i in "${!items[@]}"; do
    tui.factory.button tiles "${_TUI_FACTORY_GRID_CELLS[$i]}" 0 "${items[$i]}" pick
done
tui.relayout
```

**See also:** [`tui.factory.clear`](/api/core/tui.factory.clear.html)
