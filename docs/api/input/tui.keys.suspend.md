### `tui.keys.suspend`

```bash
tui.keys.suspend [on|off|toggle]
```

Kill switch: turns every keyboard binding off, user and default, and shows a warning box. Default: `toggle`.

**Notes**

- Mouse input keeps working. A focused text input still takes typing and Enter.
- The toggle chord (`ctrl+alt+k` by default) always works; change it with [`tui.keys.suspend_key`](/api/input/tui.keys.suspend_key.html).
- Survives page changes.
