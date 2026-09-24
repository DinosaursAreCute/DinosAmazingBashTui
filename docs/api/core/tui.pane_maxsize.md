### `tui.pane_maxsize`

```bash
tui.pane_maxsize PANE [MAX_W] [MAX_H]
```

Caps the size a split gives the pane.

**Parameters**

- `MAX_W`, `MAX_H`: columns and rows. Empty leaves that value unchanged.

**Notes**

- Space the cap takes away is passed to the pane's last sibling. When the capped pane is itself the last child, that space stays empty.

**See also:** [`tui.pane_minsize`](/api/core/tui.pane_minsize.html)
