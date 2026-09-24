### `tui.pane_border`

```bash
tui.pane_border PANE STYLE
```

Sets the border style of a pane.

**Parameters**

- `STYLE`: `single`, `double`, `heavy` or `none`. Any other value draws `single`.

**Notes**

- A parent pane draws its border only when it was set with this function and there is room for it; leaf panes draw a `single` border by default.
- A border that doesn't fit (leaf under 3×5 cells) is dropped automatically.
- While the app runs, call [`tui.relayout`](/api/core/tui.relayout.html) to apply it; the border changes the content area.

**See also:** [`tui.get.border`](/api/core/tui.get.border.html)
