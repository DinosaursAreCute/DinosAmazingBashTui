### `tui.overlay.box`

```bash
tui.overlay.box ROW COL WIDTH SGR TITLE [LINE...]
```

Draws a framed box at an absolute position. Meant for overlay and modal draw functions.

**Parameters**

- `ROW`, `COL`: top-left corner, 1-based.
- `WIDTH`: outer width including the frame.
- `SGR`: colors as SGR parameters, e.g. `1;97;44`.
- `LINE`: one per content row, cut or padded to the inner width.

**Notes**

- Saves and restores the cursor. Draws immediately; nothing is kept.
