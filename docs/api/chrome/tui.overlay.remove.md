### `tui.overlay.remove`

```bash
tui.overlay.remove DRAWFN
```

Unregisters an overlay.

**Notes**

- What it drew stays on screen until the next full repaint. Call [`tui.relayout`](/api/core/tui.relayout.html) to wipe it.
