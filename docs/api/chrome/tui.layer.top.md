### `tui.layer.top`

```bash
tui.layer.top [VAR]
```

Gets the id of the topmost visible layer. The result is printed or stored in a variable; returns `1` when no layer is visible.

**Parameters**

- `VAR` - (optional) variable name to store the result. If omitted, the id is printed.

**Returns:** `0` if a layer is visible, `1` if none.

**Notes**

- The topmost layer is the one drawn last and appears on top of all others. This is the layer raised most recently by [`tui.layer.raise`](tui.layer.raise.md), shown with [`tui.layer.show`](tui.layer.show.md), or by user interaction (clicking or focusing).
- Useful for determining which layer has priority for input or to check if a specific critical layer is on top.

**See also:** [`tui.layer.raise`](tui.layer.raise.md), [`tui.layer.active`](tui.layer.active.md)
