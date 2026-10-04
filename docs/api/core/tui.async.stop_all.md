### `tui.async.stop_all`

```bash
tui.async.stop_all
```

Ends every painter and removes the state directory.

**Notes**

- Called automatically on app exit.
- Cleans up temporary files and pipes used for painter communication.

**See also**

- [`tui.async.stop`](/api/core/tui.async.stop.html)
- [`tui.async.start`](/api/core/tui.async.start.html)
