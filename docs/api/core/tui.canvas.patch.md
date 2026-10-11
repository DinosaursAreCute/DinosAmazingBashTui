### `tui.canvas.patch`

```bash
tui.canvas.patch PANE BYTES
```

Draws `BYTES` over the canvas at once, in one flush: absolute cursor moves and cells, for example only the cells an animation changed.

**Parameters**

- `PANE`: pane id.
- `BYTES`: the cells to draw, with absolute cursor moves. Nothing is measured or cut.

**Notes**

- Use it only while [`tui.canvas.fresh`](/api/core/tui.canvas.fresh.html) returns `0`; otherwise send the whole frame with [`tui.set_canvas`](/api/core/tui.set_canvas.html).
- The caller keeps the frame in step (see [`tui.canvas.source`](/api/core/tui.canvas.source.html)). The Home page paints its banner this way: a blinking cursor is one small write, not the whole hero.
- The rows [`tui.set_canvas`](/api/core/tui.set_canvas.html) remembers are dropped, so its next frame sends every row.
