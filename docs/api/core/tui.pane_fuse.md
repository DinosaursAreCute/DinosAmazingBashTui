### `tui.pane_fuse`

```bash
tui.pane_fuse PANE BOOL
```

Fuses a pane with its siblings so neighbouring borders share one line.

**Parameters**

- `PANE` - pane id.
- `BOOL` - boolean (`true|false`), default `false`. Any other value is ignored with a warning and the call returns 1.

**Notes**

- A split fuses only when every child is a fuse pane and the split has no gap. Fused siblings overlap by one cell and the shared line gets the matching junction glyphs.
- Markup: `fuse="true"`. Call [`tui.relayout`](/api/core/tui.relayout.html) to apply it while the app runs.

**See also:** [`tui.pane_border`](/api/core/tui.pane_border.html)
