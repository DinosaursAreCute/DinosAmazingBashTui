### `tui.scroll.reset`

```bash
tui.scroll.reset PANE
```

Scrolls a scrolling pane back to its top-left corner, repainting only when it was elsewhere.

**Returns:** `1` for an unknown pane.

**Notes**

- [`tui.tabs.activate`](/api/core/tui.tabs.activate.html) calls it for the tab group's content pane when another tab is activated.
- [`tui.md.show`](/api/markdown/tui.md.show.html) calls it when it shows a different document.

**See also:** [`tui.scroll.to`](/api/core/tui.scroll.to.html), [`tui.pane_scroll`](/api/core/tui.pane_scroll.html)
