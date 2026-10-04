### `tui.async.start`

```bash
tui.async.start NAME FN [ARG...]
```

Forks FN with ARG... into the background as a painter: a function running in its own process that paints directly to the terminal with absolute cursor moves, so its frames cost the main loop nothing.

**Parameters**

- `NAME`: identifier for this painter. A second `start` with the same NAME kills the first.
- `FN`: the function to run.
- `ARG...`: arguments passed to FN.

**Notes**

- The painter runs with the process's own copy of the page state as it was at fork time, and its stdin is `/dev/null`.
- The painter process is trapped to exit cleanly on TERM, HUP and INT signals.
- The parent process id is stored in `_TUI_ASYNC_PARENT`; a painter can check `kill -0 "$_TUI_ASYNC_PARENT"` to detect when the main process is gone and exit itself.
- Painters are stopped by [`tui.async.stop`](/api/core/tui.async.stop.html), [`tui.async.stop_all`](/api/core/tui.async.stop_all.html), and automatically on app exit.

**Example**

```bash
counter_painter() {
	local count=0
	while kill -0 "$_TUI_ASYNC_PARENT" 2>/dev/null; do
		tui.async.get "counter.count" count
		count=${count:-0}
		printf '\e[2;5H%d' "$count"
		tui.async.wait 0.1
	done
}

# Start the painter
tui.async.start counter counter_painter

# In the main loop: update the counter
tui.async.put counter count 5
```

**See also**

- [`tui.async.stop`](/api/core/tui.async.stop.html)
- [`tui.async.put`](/api/core/tui.async.put.html)
- [`tui.async.wait`](/api/core/tui.async.wait.html)
