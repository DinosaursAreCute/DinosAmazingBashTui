### `tui.set_canvas`

```bash
tui.set_canvas PANE TEXT
```

Sets the pane's content to a ready-made frame: one line per row, each already as wide as the pane's content area. The pane draws the lines as they are, in its own style.

**Parameters**

- `PANE`: pane id.
- `TEXT`: the rows, separated by newlines. ANSI colours are allowed. Rows past the content area are dropped, and a row narrower than the area leaves the cells after it as they were, so write blanks.

**Notes**

- Nothing is measured or cut, which makes it much cheaper than [`tui.set_text`](/api/core/tui.set_text.html) with coloured text, and it is drawn at once, not debounced. Use it for animation (the Home page's matrix rain is drawn this way, at over 20 frames a second).
- The pane's style returns after every `ESC[0m` inside a line, so a styled cell does not turn the cells after it into the terminal's default colours.
- The pane does not report itself too small for its content: no width is measured, and any width remembered from earlier text is dropped.
- Skipped when `TEXT` equals what it set last time. While nothing else has painted since the last frame, only the rows that differ from it are sent (a blinking cursor is one row). Cleared on page change.
- For an animation that changes a few cells, [`tui.canvas.patch`](/api/core/tui.canvas.patch.html) sends only those cells.

**Example**

```bash
tick() {
	local frame="" r
	for ((r = 0; r < 5; r++)); do frame+=$'\e[32m'"$(printf '%*s' 30 '' | tr ' ' '#')"$'\e[0m\n'; done
	tui.set_canvas screen "${frame%$'\n'}"
}
tui.every 0.2 tick
```
