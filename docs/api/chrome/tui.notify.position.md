### `tui.notify.position`

```bash
tui.notify.position [POS]
```

Sets where toasts appear, or prints the current position without an argument.

**Parameters**

- `POS`: `bottom-right` (default), `bottom-left`, `bottom-center`, `top-right`, `top-left`, `top-center`.

**Returns:** `1` and a message on stderr for any other value.

**Notes**

- Lasts for this run. Persist it with `tui.config.set notify.position POS` (the Settings page does).
