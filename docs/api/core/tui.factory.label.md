### `tui.factory.label`

```bash
tui.factory.label NS PANE ROW TEXT
```

Creates a label with a generated id, tracked under namespace `NS`.

**Sets:** `_TUI_FACTORY_LAST_ID` to the new id (`__f_NS_N`).

**Notes**

- The id is not printed: stdout is the screen. Read `_TUI_FACTORY_LAST_ID` right after the call.
- `_TUI_FACTORY_LAST_ID` and `_TUI_FACTORY_GRID_CELLS` are the only underscore names app code may read.

**See also:** [`tui.label`](/api/widgets/tui.label.html), [`tui.factory.clear`](/api/core/tui.factory.clear.html)
