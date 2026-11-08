### `tui.on_change`

```bash
tui.on_change ID FN [--debounce]
```

Sets a function called as `FN ID` whenever the widget changes through the user.

**Parameters**

- `--debounce` - for list and table: the selection moves and redraws on every key, but `FN` runs once the keys stop (or every `TUI_CHANGE_DEBOUNCE_MAX` events, default 8). Use it when `FN` repaints other panes.

**Notes**

- Fires after every edit (input, password, textarea), selection move (list, table) or picked value (select).
- Not called for programmatic changes such as `tui.update` or `tui.list.set`.

**Example**

```bash
tui.on_change notes mark_dirty
mark_dirty() { tui.set_label btn_save "[ Save* ]"; }
```
