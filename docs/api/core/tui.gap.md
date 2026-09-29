### `tui.gap`

```bash
tui.gap PARENT N
```

Sets the cells left blank between a split's children.

**Parameters**

- `N`: cell count. `""` leaves it unchanged.

**Notes**

- Only a split using the [new size units](/guide/markup.html) (`%`, `fr`, `auto`, `fill`, `clamp()`) - or a non-zero gap itself - is arranged by the new engine; a split whose children are all plain integer weights and has no gap keeps the old arithmetic, unchanged.
- While the app runs, call [`tui.relayout`](/api/core/tui.relayout.html) to apply it.

**See also:** [`tui.margin`](/api/core/tui.margin.html), [`tui.hsplit`](/api/core/tui.hsplit.html)
