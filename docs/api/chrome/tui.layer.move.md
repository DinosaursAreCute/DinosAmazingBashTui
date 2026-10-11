### `tui.layer.move`

```bash
tui.layer.move ID ROW COL
```

Moves the layer's top-left corner to the specified position on the screen (1-based cells), clamped to keep the layer inside the screen. After moving, the layer stays where it was put; the layout does not re-place it on the next repaint.

**Parameters**

- `ID` - layer id.
- `ROW` - 1-based row position (clamped to screen bounds).
- `COL` - 1-based column position (clamped to screen bounds).

**Returns:** `1` when the layer is not visible.

**Notes**

- The layer's rectangle is kept inside the screen bounds; if the requested position would move part of the layer off-screen, the position is adjusted.
- A layer normally returns to its markup-specified position and size during layout. Moving a layer with this function marks it as manually placed, so it stays where you put it unless the layer is reset with [`tui.layer.reset`](tui.layer.reset.md) or resized with [`tui.layer.size`](tui.layer.size.md).
- The header of a floating layer (`float` attribute) can be dragged with the mouse to move it interactively.

**See also:** [`tui.layer.size`](tui.layer.size.md), [`tui.layer.reset`](tui.layer.reset.md), [`tui.layer.zoom`](tui.layer.zoom.md)
