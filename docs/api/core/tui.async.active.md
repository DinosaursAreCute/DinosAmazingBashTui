### `tui.async.active`

```bash
tui.async.active [NAME]
```

Returns 0 while a painter is running; 1 when none are running, or when NAME is given and that painter is not running.

**Parameters**

- `NAME`: optional. When given, check only that painter. When omitted, check whether any painter is running.

**Notes**

- This is a check function: it returns an exit code, not a value. Use it in `if` statements or as a condition.
- A painter can use `kill -0 "$_TUI_ASYNC_PARENT"` to detect when the main process is gone.

**Example**

```bash
# Check if a specific painter is running
if tui.async.active background_task; then
	echo "Background task is still running"
fi

# Check if any painter is running
if tui.async.active; then
	echo "At least one painter is running"
fi
```

**See also**

- [`tui.async.start`](/api/core/tui.async.start.html)
- [`tui.async.stop`](/api/core/tui.async.stop.html)
