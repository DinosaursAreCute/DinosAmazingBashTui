### `tui.overlay.add`

```bash
tui.overlay.add DRAWFN
```

Registers a function that draws on top of the panes after every repaint.

**Parameters**

- `DRAWFN`: draws with absolute cursor moves (e.g. [`tui.overlay.box`](/api/chrome/tui.overlay.box.html)) and keeps no state of its own.

**Notes**

- Overlays survive page changes; remove page-specific ones yourself.
- Adding the same function twice is a no-op.
