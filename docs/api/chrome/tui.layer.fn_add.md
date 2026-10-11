### `tui.layer.fn_add`

```bash
tui.layer.fn_add DRAWFN [ambient]
```

Adds a function layer to the layer stack: a layer drawn by a function instead of a pane tree.

**Parameters**

- `DRAWFN`: draws with absolute cursor moves (e.g. [`tui.overlay.box`](/api/chrome/tui.overlay.box.html)), appends to the frame and keeps no state of its own.
- `ambient`: drawn with the page and not again after a page repaint (the footer row); without it the function is redrawn after every page repaint.

**Notes**

- Function layers sit in one stack with the pane layers: ambient ones below, then the pane layers, then the others in the order they were added.
- Adding the same function twice is a no-op. [`tui.overlay.add`](/api/chrome/tui.overlay.add.html) is the same call, owned by the loading plugin.
