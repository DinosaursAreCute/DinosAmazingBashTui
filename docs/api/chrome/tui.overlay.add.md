### `tui.overlay.add`

```bash
tui.overlay.add DRAWFN
```

Adds a function layer that draws on top of the panes after every repaint (an alias of [`tui.layer.fn_add`](/api/chrome/tui.layer.fn_add.html) that a plugin owns).

**Parameters**

- `DRAWFN`: draws with absolute cursor moves (e.g. [`tui.overlay.box`](/api/chrome/tui.overlay.box.html)) and keeps no state of its own.

**Notes**

- Overlays survive page changes; remove page-specific ones yourself.
- Adding the same function twice is a no-op.
