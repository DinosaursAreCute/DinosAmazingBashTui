### `tui.input.retain`

```bash
tui.input.retain ID [true|false]
```

Sets whether an input keeps focus after Enter.

**Parameters**

- `true` (default): the cursor stays in the field, like a shell prompt or chat box.
- `false`: form style; Enter submits and leaves the field.

**Notes**

- Inputs without their own setting use `TUI_INPUT_RETAIN_ON_SUBMIT` (`1`), or the `input.retain` config key.
- Any value other than `true` means `false`.
