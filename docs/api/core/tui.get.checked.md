### `tui.get.checked`

```bash
tui.get.checked ID
```

Prints nothing; returns `0` when `ID` is a checked checkbox, else `1`.

**Notes**

- Use it in a condition: `if tui.get.checked chk_a; then ...`. [`tui.get`](/api/widgets/tui.get.html) prints the value as `0`/`1`.
