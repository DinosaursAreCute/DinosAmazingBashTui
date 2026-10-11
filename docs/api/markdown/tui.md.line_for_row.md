### `tui.md.line_for_row`

```bash
tui.md.line_for_row ROW VAR
```

Stores in `VAR` the source line (1-based) of rendered row `ROW`, using the last render.

**Parameters**

- `ROW`: the 0-based rendered row index.
- `VAR`: the variable that receives the line number.

**Notes**

- The result is `0` when the row does not exist.
