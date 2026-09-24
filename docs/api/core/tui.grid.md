### `tui.grid`

```bash
tui.grid PARENT ROWS COLS FIT ROW_WEIGHTS COL_WEIGHTS NAME...
```

Lays `NAME...` out as a grid of cells inside `PARENT`, row by row.

**Parameters**

- `ROWS`, `COLS`: grid size. Either may be `""` and is then computed from the number of names; both empty gives a near-square grid.
- `FIT`: what happens to cells with no name. `pack` (default when `""`) keeps them as empty panes; `stretch` lets the row's other cells absorb them.
- `ROW_WEIGHTS`, `COL_WEIGHTS`: space-separated weights, e.g. `"1 2"`. `""` = all `1`.
- `NAME...`: cell pane names, row-major.

**Notes**

- All six leading parameters are positional; pass `""` for the ones you skip.
- Built from a [`tui.vsplit`](/api/core/tui.vsplit.html) into rows named `PARENT_row0`, `PARENT_row1`, ... and an [`tui.hsplit`](/api/core/tui.hsplit.html) per row. Blank `pack` cells are named `PARENT_rowR_cC_blank`.
- [`tui.get.split`](/api/core/tui.get.split.html) on `PARENT` prints `v`.

**Example**

```bash
tui.grid dash 2 3 pack "" "2 1 1" cpu mem disk net io load
```

**See also:** [`tui.factory.grid`](/api/core/tui.factory.grid.html), [`tui.fixed`](/api/core/tui.fixed.html)
