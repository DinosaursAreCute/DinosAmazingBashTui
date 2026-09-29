### `tui.margin`

```bash
tui.margin ID N
```

Trims a pane's own allocated rect by `N` cells on every side.

**Parameters**

- `N`: cell count. `""` leaves it unchanged.

**Notes**

- Applied after `ID`'s parent has sized it, whichever split engine did the sizing (legacy or new).
- While the app runs, call [`tui.relayout`](/api/core/tui.relayout.html) to apply it.

**See also:** [`tui.gap`](/api/core/tui.gap.html), [`tui.pane_pad`](/api/core/tui.pane_pad.html)
