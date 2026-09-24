### `tui.render`

```bash
tui.render
```

Repaints every pane, widget and output now, as one buffered frame.

**Notes**

- Expensive. Content functions ([`tui.output`](/api/core/tui.output.html), [`tui.set_text`](/api/core/tui.set_text.html), [`tui.update`](/api/widgets/tui.update.html)) already queue their own repaint, coalesced per frame; don't call `tui.render` after them or from timers.
- Does not recompute geometry; use [`tui.relayout`](/api/core/tui.relayout.html) after layout changes.

**See also:** [`tui.redraw`](/api/core/tui.redraw.html)
