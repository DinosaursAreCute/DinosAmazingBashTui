### `tui.pane_gap`

```bash
tui.pane_gap PANE [GAP]
```

Gets or sets the gap between children of a split pane.

**Parameters**

- `GAP`: cell count left blank between children on the split axis. Omit to get the current value.

**Notes**

- Applies only to split panes (those created with [`tui.hsplit`](/api/core/tui.hsplit.html) or [`tui.vsplit`](/api/core/tui.vsplit.html)).
- While the app runs, call [`tui.relayout`](/api/core/tui.relayout.html) to apply it.

**See also:** [`tui.pane_pad`](/api/core/tui.pane_pad.html)
