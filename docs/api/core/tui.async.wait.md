### `tui.async.wait`

```bash
tui.async.wait SECONDS
```

Inside a painter: sleeps without forking, by waiting on a pipe that is held open and never written. Returns immediately after the timeout, or when the main process exits.

**Parameters**

- `SECONDS`: the timeout in seconds (can be fractional, e.g. `0.1`).

**Notes**

- More efficient than `sleep` inside a painter: it does not fork a new process.
- The wait is interrupted when the main process exits (if the painter checks `kill -0 "$_TUI_ASYNC_PARENT"` next).
- Use in painter loops to control frame rate without blocking the terminal.

**Example**

```bash
painter_fn() {
	while kill -0 "$_TUI_ASYNC_PARENT" 2>/dev/null; do
		# Draw current frame
		printf '\e[2;1H%s' "Frame painted at $(date)"
		# Wait 100 milliseconds before the next frame
		tui.async.wait 0.1
	done
}
```

**See also**

- [`tui.async.start`](/api/core/tui.async.start.html)
- [`tui.async.get`](/api/core/tui.async.get.html)
