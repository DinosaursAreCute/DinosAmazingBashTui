### `tui.button`

```bash
tui.button ID PANE ROW TEXT [ACTION]
```

Creates a focusable button.

**Parameters**

- `TEXT`: caption, drawn as given (include brackets yourself: `"[ Save ]"`).
- `ACTION`: function called as `ACTION ID` on Enter or click.

**Returns:** `1` when `ID` or `PANE` is empty.

**Notes**

- Buttons are centered in their pane unless [`tui.align`](/api/widgets/tui.align.html) or [`tui.pane_align`](/api/core/tui.pane_align.html) says otherwise.
- `ACTION` may also be a [built-in action](/api/input.html#built-in-actions) such as `tui.action.back`.

**Example**

```bash
tui.button btn_save form 3 "[ Save ]" on_save
on_save() { tui.notify "Saved $(tui.get inp_name)" success; }
```

**See also:** [`tui.on_action`](/api/widgets/tui.on_action.html), [`tui.set_label`](/api/widgets/tui.set_label.html)
