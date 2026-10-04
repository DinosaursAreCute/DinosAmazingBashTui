### `tui.layer.reset`

```bash
tui.layer.reset ID
```

Resets the layer to the position and size specified in the markup. Clears any manual moves, resizes, zoom state, and minimize state.

**Parameters**

- `ID` - layer id.

**Returns:** `1` when the layer is not visible.

**Notes**

- Calling this function undoes the effects of [`tui.layer.move`](tui.layer.move.md), [`tui.layer.size`](tui.layer.size.md), [`tui.layer.zoom`](tui.layer.zoom.md), and [`tui.layer.minimize`](tui.layer.minimize.md), returning the layer to its initial state as described by the markup attributes (`x`, `y`, `width`, `height`).

**See also:** [`tui.layer.move`](tui.layer.move.md), [`tui.layer.size`](tui.layer.size.md), [`tui.layer.zoom`](tui.layer.zoom.md), [`tui.layer.minimize`](tui.layer.minimize.md)
