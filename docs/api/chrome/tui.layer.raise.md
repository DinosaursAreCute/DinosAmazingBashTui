### `tui.layer.raise`

```bash
tui.layer.raise ID
```

Makes a layer the topmost visible layer and repaints the screen. A click inside a layer or focus moving into it raises it automatically.

**Parameters**

- `ID` - layer id.

**Returns:** `1` when the layer is not visible.

**Notes**

- The topmost layer is drawn last and appears on top of all others. Raising a layer reorders the layer stack and triggers a full repaint. Keyboard focus moving into a layer or a pointer click on any part of it also raises the layer automatically.

**See also:** [`tui.layer.top`](tui.layer.top.md), [`tui.layer.show`](tui.layer.show.md)
