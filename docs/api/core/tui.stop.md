### `tui.stop`

```bash
tui.stop
```

Asks the main loop to exit after the current iteration.

**Notes**

- Fires the `quit` hook first.
- Never asks for confirmation. Bind [`tui.action.quit`](/api/input/tui.action.quit.html) instead to respect the `confirm.quit` setting.

**See also:** [`tui.run`](/api/core/tui.run.html)
