### `tui.get.dimensions`

```bash
tui.get.dimensions [-r|--rows] [-c|--columns] [--content] [PANE]
```

Prints the size of the terminal or of a pane.

**Parameters**

- `-r`, `--rows` / `-c`, `--columns`: print only that number.
- `--content`: the pane's usable area inside border and padding.
- `PANE`: omitted = the terminal.

**Output:** `ROWS COLS`, or one number with `-r`/`-c`.

**Returns:** `1` for an unknown pane.

**Example**

```bash
read -r rows cols <<<"$(tui.get.dimensions --content chart)"
cols=$(tui.get.dimensions -c)          # terminal width
```

**See also:** [`tui.pane_size`](/api/core/tui.pane_size.html) (same numbers without a subshell)
