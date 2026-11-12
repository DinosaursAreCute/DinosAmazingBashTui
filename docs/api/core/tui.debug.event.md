### `tui.debug.event`

```bash
tui.debug.event NAME [DETAIL]
```

Counts the event NAME and appends it to the debug ring buffer; does nothing unless debugging is on (`dabt --debug`).

**Parameters**

- `NAME` - `CATEGORY.what`, e.g. `cache.page.miss`; the text before the first dot is the category.
- `DETAIL` - free text kept with the event.

**Notes**

- With categories set (`--debug=cache,render`) events of other categories are dropped.
- Hot paths guard the call with `((TUI_DEBUG))` to skip the function call when debugging is off.

**Example**

```bash
((TUI_DEBUG)) && tui.debug.event cache.page.miss "$page"
```
