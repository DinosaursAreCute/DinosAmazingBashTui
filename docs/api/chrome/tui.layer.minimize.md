### `tui.layer.minimize`

```bash
tui.layer.minimize ID
```

Toggles the layer between its normal display and a collapsed one-row title bar.

**Parameters**

- `ID` - layer id.

**Returns:** `1` when the layer is not visible.

**Notes**

- When minimized, the layer shows only its title bar (one row) with the title text and any available control buttons (close, minimize, fullscreen, reset). The content is hidden and not focusable or hit-testable.
- The layer's position and size are retained; unminimizing restores the full view. Minimizing works independently of zoom state.
- A minimized state is preserved across calls and can be saved with `persist="layout"` in the markup.
- A layer with `minimizable="true"` shows a minimize button (the `–` glyph) in its header when it has space.

**See also:** [`tui.layer.zoom`](tui.layer.zoom.md), [`tui.layer.reset`](tui.layer.reset.md)
