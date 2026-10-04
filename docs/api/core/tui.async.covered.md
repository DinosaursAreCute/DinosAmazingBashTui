### `tui.async.covered`

```bash
tui.async.covered
```

Inside a painter: returns 0 while something is open over the page (a modal, the command palette, a dialog, or a layer); 1 when the page is fully visible.

**Notes**

- A painter should paint nothing while covered: rendering on top of a modal or dialog would corrupt what is on top.
- Use in the painter loop to skip drawing when `covered` returns 0.
- The covered state is updated by the main loop as modals and layers open and close.

**Example**

```bash
painter_fn() {
	while kill -0 "$_TUI_ASYNC_PARENT" 2>/dev/null; do
		# Only paint when the page is visible
		if ! tui.async.covered; then
			printf '\e[5;10H%s' "Visible"
		fi
		tui.async.wait 0.5
	done
}
```

**See also**

- [`tui.async.start`](/api/core/tui.async.start.html)
- [`tui.async.wait`](/api/core/tui.async.wait.html)
