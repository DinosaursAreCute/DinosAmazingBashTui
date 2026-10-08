### `tui.table.row`

```bash
tui.table.row ID [INDEX [VAR]]
```

Prints a row as `a|b|c`, default the selected one. With `VAR` the row is stored in that variable instead, which costs no subshell.

**Notes**

- Split it with `tui.table.row procs "" row; IFS="|" read -r name size <<<"$row"`. Pass `""` as `INDEX` for the selected row.
