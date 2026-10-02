### `tui.list.selected`

```bash
tui.list.selected ID [VAR]
```

Prints the selected index, or `-1` when nothing is selected. With `VAR` the index is stored in that variable instead, which costs no subshell.

**Example**

```bash
tui.list.selected lst_tasks i      # no subshell
(( i >= 0 )) || return
```
