### `tui.store.unset`

```bash
tui.store.unset PAGE [ID [FIELD]]
```

Drops stored state: one field, every field of one id, or a whole page.

**Parameters**

- `PAGE`: the page file's basename.
- `ID`: optional: only this widget or pane.
- `FIELD`: optional: only this field.

**Notes**

- Does not touch the live widgets; use [`tui.page.reset`](/api/core/tui.page.reset.html) for that.

**See also:** [`tui.store.set`](/api/core/tui.store.set.html), [`tui.page.reset`](/api/core/tui.page.reset.html)
