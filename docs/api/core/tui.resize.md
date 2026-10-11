### `tui.resize`

```bash
tui.resize PANE DW DH
```

Grows `PANE` by `DW` columns and `DH` rows (negative values shrink) with the same clamping as a drag.

**Parameters**

- `PANE` - pane id.
- `DW` - integer (cells); `0` leaves that axis alone.
- `DH` - integer (cells); `0` leaves that axis alone.

**Returns:** `0` when something moved, `1` when every move was clamped flat or no split of that axis holds the pane.

**Notes**

- Ignores `resizable`: the attribute gates the user's mouse and keyboard, not the app. The layout generation is bumped, the layout recomputed and `on_resize` callbacks (`FN PANE W H`) run for panes that changed size.

**See also:** [`tui.resize.reset`](/api/core/tui.resize.reset.html), [`tui.pane_resizable`](/api/core/tui.pane_resizable.html)
