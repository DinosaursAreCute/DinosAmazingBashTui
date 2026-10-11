### `tui.md.search_info`

```bash
tui.md.search_info PANE VAR
```

Stores in `VAR` the search state of `PANE`: `3/12`, `no match`, or an empty string when no search is set.

**Parameters**

- `VAR`: the name of the variable that receives the text.

**Example**

```bash
tui.md.search_info docs info    # info="3/12"
```
