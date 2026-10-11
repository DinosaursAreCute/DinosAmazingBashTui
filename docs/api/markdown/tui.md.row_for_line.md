### `tui.md.row_for_line`

```bash
tui.md.row_for_line LINE VAR
```

Stores in `VAR` the 0-based index of the first rendered row of the block that holds source line `LINE` (1-based).

**Parameters**

- `LINE`: the 1-based source line.
- `VAR`: the variable that receives the row index.

**Notes**

- Uses the map of the last [`tui.md.render`](/api/markdown/tui.md.render.html). The result is `0` when `LINE` is before the first block.
- Use it to keep the scroll position when switching between the source and the rendered view.
