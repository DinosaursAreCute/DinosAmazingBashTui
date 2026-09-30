### `tui.paint.reset`

```bash
tui.paint.reset
```

Clears the rendering cache, forcing a full redraw on the next flush.

**Notes**

- Use this after the terminal was resized drastically, taken over by another process, or when a full erase has blanked the physical screen.
- Comparing against old cached rows would be meaningless; the next flush must resend everything unconditionally.

**See also:** [`tui.render`](/api/core/tui.render.html)
