### `tui.async.emit`

```bash
tui.async.emit FRAME [PREFIX]
```

Inside a painter: sends FRAME to the terminal. A painter's stdout is closed, so this is the only way it draws.

**Parameters**

- `FRAME`: absolute cursor moves and cells, as small as possible (changes only).
- `PREFIX`: the style the frame starts with. It is repeated at the start of each piece when the frame is cut in pieces.

**Notes**

- The frame goes out through the same writer as the main loop's frames, one write call per piece, so it never lands inside what the main loop is writing and the main loop's never inside it.
- A painter can skip a frame when [`tui.async.get`](/api/core/tui.async.get.html) `gen VAR` shows the main loop has written since the painter's last frame, so a highlight never queues behind an animation.

**See also**

- [`tui.async.start`](/api/core/tui.async.start.html)
- [`tui.async.covered`](/api/core/tui.async.covered.html)
