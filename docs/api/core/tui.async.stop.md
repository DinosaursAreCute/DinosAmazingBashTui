### `tui.async.stop`

```bash
tui.async.stop NAME
```

Ends the painter named NAME, if it exists.

**Parameters**

- `NAME`: the painter's identifier, as given to [`tui.async.start`](/api/core/tui.async.start.html).

**Notes**

- Returns 0 whether or not a painter by that name exists.
- Sends SIGTERM to the process and waits for it to exit.
- Called automatically by [`tui.async.stop_all`](/api/core/tui.async.stop_all.html), and on app exit.

**See also**

- [`tui.async.start`](/api/core/tui.async.start.html)
- [`tui.async.stop_all`](/api/core/tui.async.stop_all.html)
