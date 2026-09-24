### `tui.label`

```bash
tui.label ID PANE ROW TEXT
```

Creates a static text widget.

**Parameters**

- `ID`: unique widget id.
- `PANE`: a leaf pane.
- `ROW`: 0-based row inside the pane's content area, counted from the pane's vertical anchor (see [`tui.pane_valign`](/api/core/tui.pane_valign.html)).
- `TEXT`: the text.

**Returns:** `1` and a message on stderr when `ID` or `PANE` is empty.

**Notes**

- Not focusable. Change the text with [`tui.set_label`](/api/widgets/tui.set_label.html) or [`tui.update`](/api/widgets/tui.update.html).
- Create widgets before the first render, or call [`tui.relayout`](/api/core/tui.relayout.html) afterwards.

**Example**

```bash
tui.label lbl_name form 0 "Name"
```
