### `tui.async.put`

```bash
tui.async.put NAME KEY VALUE
```

The main loop's way to send a small value to a painter: writes VALUE to a temporary file that the painter can read with [`tui.async.get`](/api/core/tui.async.get.html).

**Parameters**

- `NAME`: the painter's identifier, as given to [`tui.async.start`](/api/core/tui.async.start.html).
- `KEY`: the key name for this value.
- `VALUE`: the value to send (typically a size, mask, or flag).

**Notes**

- The file is stored at `$_TUI_ASYNC_DIR/$NAME.$KEY`. Use short values: the file is read with `read -r`, so long values are truncated.
- Intended for passing configuration or state updates: rectangles, masks, coordinates, small strings.
- Multiple calls with the same NAME and KEY overwrite the previous value.

**Example**

```bash
# Tell the painter to draw a 20x10 rectangle
tui.async.put my_painter viewport "20x10"

# Update the painter with new mask data
tui.async.put my_painter mask "1010101010"
```

**See also**

- [`tui.async.get`](/api/core/tui.async.get.html)
- [`tui.async.start`](/api/core/tui.async.start.html)
