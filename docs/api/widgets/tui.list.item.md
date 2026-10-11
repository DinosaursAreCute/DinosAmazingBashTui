### `tui.list.item`

```bash
tui.list.item ID [INDEX [VAR]]
```

Prints the item at `INDEX`, default the selected one. Prints nothing for an index out of range. With `VAR` the item is stored in that variable instead (empty for an index out of range), which costs no subshell. Pass `""` as `INDEX` for the selected item.
