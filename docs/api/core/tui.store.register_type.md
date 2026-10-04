### `tui.store.register_type`

```bash
tui.store.register_type TYPE FIELD...
```

Sets which fields a widget type keeps.

**Parameters**

- `TYPE`: the widget type, as in `_TUI_W_TYPE`.
- `FIELD`: `value`, `cursor`, `scroll`, `sel`, or a field of your own.

**Notes**

- Built in: `input`, `password`, `textarea` (`value cursor scroll`), `checkbox`, `progress` (`value`), `select` (`value sel`), `list`, `table` (`sel scroll`).
- A field of your own needs `_tui_store.get.FIELD ID` (sets `_SF`, rc 1 = nothing to keep) and `_tui_store.put.FIELD ID VALUE`.

**See also:** [`tui.store.set`](/api/core/tui.store.set.html)
