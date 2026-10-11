### `tui.page.resettable`

```bash
tui.page.resettable
```

Reports whether a reset would change anything on the current page.

**Returns:** `0` when a split was resized or a kept field differs from its first-build value, `1` otherwise.

**Notes**

- The footer item `Reset page` and the palette command of the same name use it as their `when` predicate.

**See also:** [`tui.page.reset`](/api/core/tui.page.reset.html)
