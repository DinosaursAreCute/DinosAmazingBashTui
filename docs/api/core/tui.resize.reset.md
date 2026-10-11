### `tui.resize.reset`

```bash
tui.resize.reset PANE
```

Restores the split weights recorded before the first resize, for the split holding `PANE` and every split above it.

**Parameters**

- `PANE` - pane id.

**Returns:** `1` when nothing had been resized.

**Notes**

- The record is dropped on a page load, so a reset returns to the weights the page was built with. A double press on a handle calls it.

**See also:** [`tui.resize`](/api/core/tui.resize.html)
