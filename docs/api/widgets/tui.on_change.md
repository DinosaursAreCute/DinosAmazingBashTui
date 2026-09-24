### `tui.on_change`

```bash
tui.on_change ID FN
```

Sets a function called as `FN ID` whenever the widget changes through the user.

**Notes**

- Fires after every edit (input, password, textarea), selection move (list, table) or picked value (select).
- Not called for programmatic changes such as `tui.update` or `tui.list.set`.

**Example**

```bash
tui.on_change notes mark_dirty
mark_dirty() { tui.set_label btn_save "[ Save* ]"; }
```
