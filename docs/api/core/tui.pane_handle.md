### `tui.pane_handle`

```bash
tui.pane_handle PANE KIND
```

Chooses the mouse handle that resizes a resizable pane.

**Parameters**

- `PANE` - pane id.
- `KIND` - enum (corner|edge|divider|none), default none. Selects the mouse handle style for resizing.

**Notes**

- `edge` and `divider` drag a border the pane shares with a sibling; `divider` is the shared line of a fused split. A pane that has a next sibling drags its trailing border (its last column / row); the last child of a split drags its leading border (its first column / row, shared with the previous sibling), so it can be resized too. A pane with `resizable` but no handle stays keyboard-only. `corner` is the pane's bottom-right cell: it moves the nearest ancestor h-split edge horizontally and the nearest v-split edge vertically.
- A double press on a handle resets the pane ([`tui.resize.reset`](/api/core/tui.resize.reset.html)). The zones are rebuilt with every layout.
- Markup: `handle="corner|edge|divider|none"`; it needs `resizable`. An invalid value is ignored with a warning (return `1`).

**See also:** [`tui.pane_resizable`](/api/core/tui.pane_resizable.html)
