### `tui.exists`

```bash
tui.exists ID
```

Succeeds when a widget, a pane or a layer has that id. Prints nothing and does not fork, so it is safe in a callback that runs often.

**Returns:** `0` when the id exists, `1` when it does not or `ID` is empty.

**Notes**

- Use it to guard a callback that may run on a page where the widget is not (a poll that updates a tile of another page). [`tui.get.type`](/api/core/tui.get.type.html) only answers for widgets.

**Example**

```bash
tui.exists lbl_sent && tui.set_label lbl_sent "requests: $count"
```
