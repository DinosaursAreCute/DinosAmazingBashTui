### `tui.pane_title_align`

```bash
tui.pane_title_align PANE ALIGN
```

Sets where along its border line a pane's title sits.

**Parameters**

- `PANE` - pane id.
- `ALIGN` - enum (left|center|right), default left. A title longer than the line is cut.

**Notes**

- Markup: `title_align="center"`. An invalid value is ignored with a warning.

**See also:** [`tui.pane_border`](/api/core/tui.pane_border.html)
