### `tui.hsplit`

```bash
tui.hsplit PARENT NAME[:WEIGHT]...
```

Splits `PARENT` into side-by-side child panes.

**Parameters**

- `PARENT`: an existing pane (`root` at first).
- `NAME[:WEIGHT]`: one per child, left to right. `WEIGHT` is a positive integer share of the width. Default: `1`.

**Notes**

- Pane names become part of bash variable names: use letters, digits and `_` only.
- Each child starts with a `single` border and no title. The last child absorbs rounding leftovers.

**Example**

```bash
tui.hsplit root nav main:3      # nav gets 1/4 of the width, main 3/4
```

**See also:** [`tui.vsplit`](/api/core/tui.vsplit.html), [`tui.grid`](/api/core/tui.grid.html), [`tui.fixed`](/api/core/tui.fixed.html)
