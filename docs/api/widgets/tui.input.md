### `tui.input`

```bash
tui.input ID PANE ROW [PLACEHOLDER] [LABEL] [SUBMIT]
```

Creates a single-line text input.

**Parameters**

- `PLACEHOLDER`: grey text shown while empty.
- `LABEL`: text drawn before the field.
- `SUBMIT`: function called on Enter as `SUBMIT ID TEXT`: the widget id, then the current text.

**Returns:** `1` when `ID` or `PANE` is empty.

**Notes**

- The id lets one function serve several inputs: `case $1 in inp_name) ... ;; inp_mail) ... ;; esac`.
- Without `SUBMIT`, an action set with [`tui.on_action`](/api/widgets/tui.on_action.html) is called as `ACTION ID` instead.
- The text is not cleared after submit. Clear it in `SUBMIT` with `tui.update ID ""`.
- The input keeps focus after Enter by default; see [`tui.input.retain`](/api/widgets/tui.input.retain.html).
- Full editing keys (selection, word jumps, clipboard, undo): press `f1` in the app, or see [`tui.action.text_keys`](/api/widgets/tui.action.text_keys.html).

**Example**

```bash
tui.input inp_cmd shell 0 "type a command" "> " run_cmd
run_cmd() { tui.output_append log "\$ $2"; tui.update "$1" ""; }     # $1 = this input's id, $2 = the text
```

**See also:** [`tui.password`](/api/widgets/tui.password.html), [`tui.textarea`](/api/widgets/tui.textarea.html)
