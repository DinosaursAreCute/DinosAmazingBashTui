### `tui.md.click`

```bash
tui.md.click PANE X Y
```

Follows the link drawn under the screen cell `X`,`Y` of `PANE`, exactly like focusing it and calling [`tui.md.link_open`](tui.md.link_open.md). A left click on a link in a Markdown pane does this by itself.

**Notes**

- Returns 1 when the cell is not on a link (the click is then an ordinary click on the pane).
- Links that wrap onto the next row are followed from either row.

**Example**

```bash
tui.md.click docs "$TUI_EVENT_X" "$TUI_EVENT_Y"
```
