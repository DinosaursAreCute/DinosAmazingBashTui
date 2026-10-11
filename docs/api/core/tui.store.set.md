### `tui.store.set`

```bash
tui.store.set PAGE ID FIELD VALUE
```

Stores one field of a widget or pane in the page-state store.

**Parameters**

- `PAGE`: the page file's basename, e.g. `workspace.xml`.
- `ID`: widget or pane id (a `|` or `%` in it is escaped, so ids never collide).
- `FIELD`: `value`, `cursor`, `scroll`, `sel`, `collapsed` or `size`.
- `VALUE`: the text to keep.

**Notes**

- The store is one associative array, `_TUI_STORE["PAGE|ID|FIELD"]`, kept for the session. Pages fill it themselves when `keep_value`, `keep_collapsed`, `keep_size` or `keep_state` is set; call this to preload or edit state. It changes memory only; the disk file (`persist="disk"`) is written from the live widgets when a page is left, see [`tui.store.flush`](/api/core/tui.store.flush.html).

**See also:** [`tui.store.get`](/api/core/tui.store.get.html), [`tui.page.reset`](/api/core/tui.page.reset.html)
