### `tui.expand`

```bash
tui.expand ID VAL
```

Grows a widget to fill the rest of its pane's content height, width, or both.

**Parameters**

- `VAL`: `x`, `y` or `both`. `""` leaves it unchanged.

**Notes**

- `y`/`both` is what `textarea`, `list` and `table` set for themselves at creation (the old hardcoded behaviour); any other widget opts in to multi-row sizing the same way.
- A widget's width already fills its pane's content width by default, so `x` alone is currently a no-op; it's accepted for forward compatibility with a future per-axis sizing model.

**See also:** [`tui.minsize`](/api/widgets/tui.minsize.html), [`tui.maxsize`](/api/widgets/tui.maxsize.html)
