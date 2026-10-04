### `tui.store.get`

```bash
tui.store.get PAGE ID FIELD
```

Reads one stored field into `REPLY`.

**Parameters**

- `PAGE`: the page file's basename.
- `ID`: widget or pane id.
- `FIELD`: the field name.

**Returns:** `0` with the value in `REPLY`, `1` when nothing is stored.

**Notes**

- Fork-free.

**See also:** [`tui.store.set`](/api/core/tui.store.set.html)
