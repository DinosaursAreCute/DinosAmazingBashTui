### `tui.table.row`

```bash
tui.table.row ID [INDEX]
```

Prints a row as `a|b|c`, default the selected one.

**Notes**

- Split it with `IFS="|" read -r name size <<<"$(tui.table.row procs)"`.
