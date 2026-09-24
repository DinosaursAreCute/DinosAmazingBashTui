### `tui.select`

```bash
tui.select ID PANE ROW LABEL [ACTION]
```

Creates a one-row dropdown. Enter, Space, Down or a click opens a picker dialog.

**Parameters**

- `LABEL`: text before the value, also the picker title.
- `ACTION`: called as `ACTION ID` after a new value is picked.

**Notes**

- Read the value with [`tui.get`](/api/widgets/tui.get.html), the index with [`tui.select.index`](/api/widgets/tui.select.index.html).

**Example**

```bash
tui.select mode form 3 "Mode:" mode_changed
tui.select.set mode fast balanced careful
```
