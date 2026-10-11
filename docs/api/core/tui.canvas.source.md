### `tui.canvas.source`

```bash
tui.canvas.source PANE FN
```

Names the function that keeps the frame of a canvas pane, for an animation that draws changes with [`tui.canvas.patch`](/api/core/tui.canvas.patch.html) instead of sending the whole frame.

**Parameters**

- `PANE`: pane id.
- `FN`: called as `FN PANE` before every full paint of the pane (a page render, a resize, a layer closing over it). It sets `_TUI_PANE_RAW[PANE]` to the whole frame as [`tui.set_canvas`](/api/core/tui.set_canvas.html) takes it.

**Notes**

- Cleared on page change.
