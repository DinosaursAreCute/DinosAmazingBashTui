### `tui.layer.size`

```bash
tui.layer.size ID HEIGHT WIDTH
```

Sets the layer's size in cells. The minimum is 3 rows by 8 columns; the maximum is the screen size. The position is adjusted if needed to keep the layer inside the screen.

**Parameters**

- `ID` - layer id.
- `HEIGHT` - height in rows (clamped to 3..screen height).
- `WIDTH` - width in columns (clamped to 8..screen width).

**Returns:** `1` when the layer is not visible.

**Notes**

- If the requested size is too small, it is enlarged to the minimum (3x8). If it exceeds the screen, it is shrunk to fit.
- Like [`tui.layer.move`](tui.layer.move.md), sizing a layer marks it as manually placed and kept as-is on the next layout. Reset it with [`tui.layer.reset`](tui.layer.reset.md) to return to the markup-specified size.
- A floating layer's bottom-right corner can be dragged with the mouse to resize it interactively.

**See also:** [`tui.layer.move`](tui.layer.move.md), [`tui.layer.reset`](tui.layer.reset.md)
