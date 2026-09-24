### `tui.clock`

```bash
tui.clock PANE [FORMAT] [FONT] [ID]
```

Shows a live clock in a pane, updated on every whole second.

**Parameters**

- `FORMAT`: `strftime` format. Default: `%H:%M:%S`.
- `FONT`: a banner font (`block5`, `seg3`, `box3`, `blk3`, `half2`) for big digits, styled with the pane's colors. Empty: plain text.
- `ID`: timer id. Default: `clock_PANE`.

**Notes**

- Stops itself when `PANE` no longer exists.
- Loads `terminal_renderer.sh` on first use of a font.

**Example**

```bash
tui.clock header_clock "%a %H:%M" seg3
```
