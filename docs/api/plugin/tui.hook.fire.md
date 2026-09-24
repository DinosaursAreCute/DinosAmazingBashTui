### `tui.hook.fire`

```bash
tui.hook.fire EVENT [ARG...]
```

Calls every handler of `EVENT` with the arguments. Returns `0` when at least one handler returned `0`, else `1`.

**Notes**

- Handlers whose function no longer exists are skipped.
- Apps may fire their own events for their plugins.
