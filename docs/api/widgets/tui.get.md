### `tui.get`

```bash
tui.get ID
```

Prints a widget's value, without a trailing newline.

**Output:** by type: input, password and textarea: the text (textarea lines joined by newlines); checkbox: `0` or `1`; label: its text; select: the chosen option; progress: the percent. Buttons, lists and tables print nothing; use [`tui.list.item`](/api/widgets/tui.list.item.html) / [`tui.table.row`](/api/widgets/tui.table.row.html).

**Example**

```bash
name="$(tui.get inp_name)"
```
