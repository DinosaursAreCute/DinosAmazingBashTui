### `tui.content_area`

```bash
tui.content_area PANE
```

Prints the content rectangle of a pane as `ROW COL HEIGHT WIDTH` (1-based, inside border and padding).

**Notes**

- Does not check that `PANE` exists. Prefer [`tui.get.content_area`](/api/core/tui.get.content_area.html), which returns `1` for an unknown pane.
