### `tui.get`

```bash
tui.get ID [VAR]
```

Prints a widget's value, without a trailing newline, or with `VAR` stores it in the variable `VAR`.

**Output:** by type: input, password and textarea: the text (textarea lines joined by newlines); checkbox: `0` or `1`; label: its text; select: the chosen option; progress: the percent. Buttons, lists and tables print nothing; use [`tui.list.item`](/api/widgets/tui.list.item.html) / [`tui.table.row`](/api/widgets/tui.table.row.html).

**Notes**

- `$(tui.get ID)` starts a subshell on every call. Pass a variable name instead wherever the call is frequent: in a callback that reads several widgets, in a handler of a key or mouse event, or inside a loop.

**Example**

```bash
tui.get inp_name name          # no subshell
name="$(tui.get inp_name)"     # works too, one subshell
```
