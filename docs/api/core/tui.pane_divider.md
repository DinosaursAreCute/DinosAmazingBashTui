### `tui.pane_divider`

```bash
tui.pane_divider PANE STYLE
```

Sets the border style of the line a fused pane shares with its neighbour.

**Parameters**

- `PANE` - pane id.
- `STYLE` - enum (single|double|heavy), optional. Empty uses the pane's own border style.

**Notes**

- Markup: `divider="double"`. Only matters on a fused pane.

**See also:** [`tui.pane_border`](/api/core/tui.pane_border.html)
