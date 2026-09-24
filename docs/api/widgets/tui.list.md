### `tui.list`

```bash
tui.list ID PANE ROW [ACTION] [ROWS]
```

Creates a scrollable single-choice list.

**Parameters**

- `ACTION`: called as `ACTION ID` on Enter or double-click.
- `ROWS`: height. Omitted or `0`: fill the pane.

**Notes**

- Keys: Up/Down, PgUp/PgDn, Home/End. At the first/last row Up/Down move focus out.
- Selection moves call the [`tui.on_change`](/api/widgets/tui.on_change.html) function.

**Example**

```bash
tui.list files side 0 open_file
tui.list.set files *.txt
open_file() { tui.output view "$(<"$(tui.list.item "$1")")"; }
```
