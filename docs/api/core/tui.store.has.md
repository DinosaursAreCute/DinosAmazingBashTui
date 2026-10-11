### `tui.store.has`

```bash
tui.store.has PAGE [ID]
```

Reports whether anything is stored for a page, or for one id.

**Parameters**

- `PAGE`: the page file's basename.
- `ID`: optional: only this widget or pane.

**Returns:** `0` when something is stored, `1` otherwise.

**See also:** [`tui.store.get`](/api/core/tui.store.get.html)
