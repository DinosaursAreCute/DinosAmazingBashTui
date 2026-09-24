### `tui.relayout`

```bash
tui.relayout [PANE]
```

Recomputes geometry and repaints in one synchronized frame. Use it after changing borders, padding, titles or splits while the app runs.

**Parameters**

- `PANE`: a leaf pane to repaint alone, without clearing the screen. Omitted (or a parent pane): lay out and repaint everything.

**Notes**

- Before [`tui.run`](/api/core/tui.run.html) it only recomputes geometry.

**Example**

```bash
tui.pane_border side double
tui.relayout
```
