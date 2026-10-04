### `tui.pane_resizable`

```bash
tui.pane_resizable PANE MODE
```

Allows a pane to be resized on one or both axes, by mouse handle or keyboard.

**Parameters**

- `PANE` - pane id.
- `MODE` - enum (x|y|both|none). `x` resizes width, `y` resizes height, `both` allows both axes, `none` switches resizing off.

**Notes**

- Markup: `resizable="x|y|both"`. Works on any pane. A resize moves weight between the pane and a sibling: its next sibling, or the previous one for the last child of a split (keyboard and drag alike) in proportion to the weights they hold now, within their `min_*`/`max_*`.
- Mouse zones need [`tui.pane_handle`](/api/core/tui.pane_handle.html); without one `alt+r` still starts the keyboard resize mode.
- An invalid value is ignored with a warning (return `1`).

**See also:** [`tui.resize`](/api/core/tui.resize.html), [`tui.action.resize_mode`](/api/input/tui.action.resize_mode.html)
