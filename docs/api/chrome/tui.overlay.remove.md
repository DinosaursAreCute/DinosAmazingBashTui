### `tui.overlay.remove`

```bash
tui.overlay.remove DRAWFN
```

Removes a function layer (an alias of [`tui.layer.fn_remove`](/api/chrome/tui.layer.fn_remove.html)).

**Notes**

- What it drew stays on screen until the next full repaint. Call [`tui.relayout`](/api/core/tui.relayout.html) to wipe it.
