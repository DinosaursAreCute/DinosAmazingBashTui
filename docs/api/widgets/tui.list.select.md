### `tui.list.select`

```bash
tui.list.select ID INDEX
```

Moves the selection to `INDEX` (0-based), clamped to the list. A negative index clears it.

**Notes**

- Does not call the `on_change` function.
