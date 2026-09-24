### `tui.fixed`

```bash
tui.fixed PARENT CELL_W CELL_H CHILD[:SPAN[:nl]]...
```

Lays children out as fixed-size cells that flow left to right and wrap, like keys on a keyboard.

**Parameters**

- `CELL_W`, `CELL_H`: size of one cell in columns and rows.
- `CHILD`: pane name. `SPAN` makes it that many cells wide (default `1`). A third field (any text, e.g. `nl`) starts a new row before this child.

**Notes**

- Sizes never stretch with the window. Children that don't fit get a 0×0 rectangle and are not drawn.
- Children start with no border.
- [`tui.get.split`](/api/core/tui.get.split.html) on `PARENT` prints `f`.

**Example**

```bash
tui.fixed keys 6 3 esc f1 f2 f3 tab:2:nl q w e
```

**See also:** [`tui.grid`](/api/core/tui.grid.html)
