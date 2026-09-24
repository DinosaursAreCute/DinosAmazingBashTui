### `tui.update`

```bash
tui.update ID VALUE
```

Sets a widget's value and redraws the widget.

**Notes**

- Does not call the widget's action or `on_change` function.
- For a button or checkbox caption use [`tui.set_label`](/api/widgets/tui.set_label.html); `VALUE` is not the caption.

**Example**

```bash
tui.update inp_name ""          # clear an input
tui.update chk_wrap 1           # check a checkbox without running its action
```
