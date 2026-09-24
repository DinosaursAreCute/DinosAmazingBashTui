### `tui.select.pick`

```bash
tui.select.pick ID INDEX
```

Chooses option `INDEX` (0-based) as if the user picked it: sets the value, redraws, then calls the `on_change` function and the action.

**Returns:** `1` for an index out of range.
