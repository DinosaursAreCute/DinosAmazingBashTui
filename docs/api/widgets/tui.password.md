### `tui.password`

```bash
tui.password ID PANE ROW [PLACEHOLDER] [LABEL] [SUBMIT]
```

Creates a single-line input that shows `•` for each character.

**Notes**

- Same parameters and `SUBMIT ID TEXT` call as [`tui.input`](/api/widgets/tui.input.html). Read the value with [`tui.get`](/api/widgets/tui.get.html).
- Copy and cut are disabled, so the text never reaches the clipboard.
