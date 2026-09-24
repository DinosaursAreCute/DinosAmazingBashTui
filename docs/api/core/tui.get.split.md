### `tui.get.split`

```bash
tui.get.split PANE
```

Prints how a pane is split: `h`, `v`, `f` (fixed) or empty for a leaf. Returns `1` for an unknown pane.

**Notes**

- A pane built with `tui.grid` prints `v`: a grid is a vertical split into rows.
