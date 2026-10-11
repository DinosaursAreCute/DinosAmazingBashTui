### `tui.layer.show`

```bash
tui.layer.show ID
```

Shows a hidden layer on top, restoring it to visibility. A modal layer takes the focus scope and remembers the focused widget; a layer with a timeout attribute hides itself after the specified seconds.

**Parameters**

- `ID` - layer id.

**Returns:** `1` for an unknown id.

**Notes**

- A hidden layer is not drawn, not hit-testable, and its widgets are not focusable. Showing a layer places it at the top of the stack. For a modal layer (created with `<modal>` or `modal="true"`), the focus scope is restricted to the layer's widgets while it is shown; the previously focused widget outside the layer is remembered and restored when the layer hides.
- A layer with `timeout=SECONDS` (as an integer or `EPOCHREALTIME` seconds) automatically calls `tui.layer.hide` after that many seconds pass.
- Markup tags: `<window>`, `<modal>`, `<dialog>`, `<popup>`, `<tooltip>`, `<contextmenu>`, `<toast>` (see [`tui.layer` overview](#overview)).

**See also:** [`tui.layer.hide`](tui.layer.hide.md), [`tui.layer.toggle`](tui.layer.toggle.md), [`tui.layer.active`](tui.layer.active.md), [`tui.layer.top`](tui.layer.top.md)
