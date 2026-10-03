### `tui.scroll.to`

```bash
tui.scroll.to TARGET [top|center|bottom]
```

Scrolls the pane that holds widget `TARGET` (or the pane `TARGET` itself) so the widget sits at the specified viewport position.

**Parameters**

- `TARGET`: a widget id or pane id
- Position (optional): `top`, `center`, or `bottom`
  - For widgets: positions the widget's top, middle, or bottom row at that viewport edge
  - For panes: positions the start (top), middle, or end of content at that edge
  - Omitted (default): performs the minimal scroll needed to show it; for panes, equivalent to `top`

**Returns**

- `0` on success
- `1` for an unknown id, a non-scrolling pane, or an invalid position

**Notes**

- The offset is clamped to the valid range `[0, max]` for the pane's content.
- Repaints only when the offset actually changed: full redraw for widget panes, targeted update for output panes.
- If the UI is not running, only sets the offset without drawing.

**See also:** [`tui.pane_scroll`](/api/core/tui.pane_scroll.html), [`tui.get.scroll`](/api/core/tui.get.scroll.html)
