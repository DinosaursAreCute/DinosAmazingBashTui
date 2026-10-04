### `tui.async.get`

```bash
tui.async.get KEY VAR
```

Inside a painter: reads a value sent by the main loop via [`tui.async.put`](/api/core/tui.async.put.html) into VAR.

**Parameters**

- `KEY`: the key to read. Use `NAME.KEY` format, where NAME is the painter's identifier from [`tui.async.start`](/api/core/tui.async.start.html).
- `VAR`: the variable to store the value in (passed by name, not reference).

**Notes**

- Returns 0 always. If the key does not exist, VAR is set to an empty string.
- The file is read with `IFS= read -r`, so trailing whitespace and newlines are preserved, but the line is truncated at the first newline by the shell's `read` builtin.
- Typically used inside the painter loop to receive updates from the main process.

**Example**

```bash
painter_fn() {
	local count
	while kill -0 "$_TUI_ASYNC_PARENT" 2>/dev/null; do
		tui.async.get "mypaint.count" count
		count=${count:-0}
		printf '\e[2;5H%d' "$count"
		tui.async.wait 0.1
	done
}
```

**See also**

- [`tui.async.put`](/api/core/tui.async.put.html)
- [`tui.async.start`](/api/core/tui.async.start.html)
