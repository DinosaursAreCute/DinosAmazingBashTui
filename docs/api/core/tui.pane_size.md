### `tui.pane_size`

```bash
tui.pane_size PANE
```

Stores the usable content size of a pane (inside border and padding) in variables, without a subshell.

**Returns:** `1` for an unknown pane.

**Sets:** `TUI_PANE_ROWS`, `TUI_PANE_COLS`.

**Example**

```bash
tui.pane_size status
printf -v rule '%*s' "$TUI_PANE_COLS" ''
tui.set_text status "${rule// /─}"      # a rule exactly as wide as the pane
```

**See also:** [`tui.get.dimensions`](/api/core/tui.get.dimensions.html)
