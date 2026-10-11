### `tui.pane_scroll_into_view`

```bash
tui.pane_scroll_into_view PANE true|false
```

Sets whether focus scrolls a vertically scrolling pane to reveal the focused widget. Default: `true`.

**Notes**

- Applies to panes created with `scroll_into_view="true|false"` in markup.
- When enabled, the pane scrolls automatically to keep the focused widget visible in the viewport.

**See also:** [`tui.pane_scroll`](/api/core/tui.pane_scroll.html)
