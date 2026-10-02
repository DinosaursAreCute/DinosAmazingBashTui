### `tui.frame.request`

```bash
tui.frame.request
```

Asks for a relayout and repaint at the end of the current input-loop iteration.

**Notes**

- Any number of requests inside one event produce one frame. Use it instead of [`tui.relayout`](/api/core/tui.relayout.html) in handlers that change several things.
- A direct [`tui.render`](/api/core/tui.render.html) satisfies a pending request.

**See also:** [`tui.relayout`](/api/core/tui.relayout.html), [`tui.render`](/api/core/tui.render.html)
