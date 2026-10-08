### `tui.table.align`

```bash
tui.table.align ID SPEC
```

Sets the alignment of each table column (header and cells).

**Parameters**

- `SPEC`: one letter per column, separated by `|`: `l` left (default) or `r` right. Columns left out stay left.

**Example**

```bash
tui.table.align procs "r|l|l|r|r|r"   # numbers right-aligned
```
