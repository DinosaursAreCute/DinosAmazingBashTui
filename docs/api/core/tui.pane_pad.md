### `tui.pane_pad`

```bash
tui.pane_pad PANE HPAD VPAD
```

Sets blank columns (`HPAD`) and rows (`VPAD`) on each side inside the pane.

**Parameters**

- `HPAD`, `VPAD`: cell counts. `""` leaves that value unchanged.

**Notes**

- On a parent pane: the gap between its frame and its children. On a leaf: shrinks the area for widgets and output.
- Padding is clamped so at least one row and column remain.
- While the app runs, call [`tui.relayout`](/api/core/tui.relayout.html) to apply it.

**See also:** [`tui.get.pad`](/api/core/tui.get.pad.html), [`tui.pad`](/api/widgets/tui.pad.html)
