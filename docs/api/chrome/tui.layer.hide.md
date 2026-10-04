### `tui.layer.hide`

```bash
tui.layer.hide ID
```

Hides a visible layer, removing it from display. A modal layer gives the focus back to the widget that had focus before the layer opened.

**Parameters**

- `ID` - layer id.

**Returns:** `1` when the layer is not visible.

**Notes**

- A hidden layer is not drawn, not hit-testable, and its widgets are not focusable. For a modal layer, focus is restored to the widget that had focus in the page before the modal opened, if it still exists and is not hidden.
- Markup tags: `<window>`, `<modal>`, `<dialog>`, `<popup>`, `<tooltip>`, `<contextmenu>`, `<toast>`.

**See also:** [`tui.layer.show`](tui.layer.show.md), [`tui.layer.close`](tui.layer.close.md), [`tui.layer.toggle`](tui.layer.toggle.md)
