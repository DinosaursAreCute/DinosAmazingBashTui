### `tui.layer.active`

```bash
tui.layer.active [ID]
```

Returns `0` while any layer is shown, or while a specific layer is shown.

**Parameters**

- `ID` - (optional) layer id. If provided, checks only that layer; if omitted, checks if any layer is visible.

**Returns:** `0` if the condition is met, `1` otherwise.

**Notes**

- A layer is considered active (shown) when it has been made visible with [`tui.layer.show`](tui.layer.show.md) and has not been hidden with [`tui.layer.hide`](tui.layer.hide.md) or [`tui.layer.close`](tui.layer.close.md).
- Useful for conditional logic: check if a modal layer is in effect before allowing certain operations.

**See also:** [`tui.layer.show`](tui.layer.show.md), [`tui.layer.hide`](tui.layer.hide.md), [`tui.layer.top`](tui.layer.top.md)
