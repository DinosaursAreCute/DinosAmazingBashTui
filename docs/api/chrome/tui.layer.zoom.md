### `tui.layer.zoom`

```bash
tui.layer.zoom ID
```

Toggles the layer between its normal size and filling the entire screen.

**Parameters**

- `ID` - layer id.

**Returns:** `1` when the layer is not visible.

**Notes**

- When zoomed, the layer covers the entire screen from (1,1) to the bottom-right corner, regardless of its previous position and size. Zooming again returns the layer to its previous dimensions. Zooming and unzooming does not affect the manual position or size set by [`tui.layer.move`](tui.layer.move.md) or [`tui.layer.size`](tui.layer.size.md).
- A zoomed state is preserved across calls and can be saved with `persist="layout"` in the markup.

**See also:** [`tui.layer.minimize`](tui.layer.minimize.md), [`tui.layer.reset`](tui.layer.reset.md)
