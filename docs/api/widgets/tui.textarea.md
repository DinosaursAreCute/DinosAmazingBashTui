### `tui.textarea`

```bash
tui.textarea ID PANE ROW [PLACEHOLDER] [ROWS] [SUBMIT]
```

Creates a multi-line text editor.

**Parameters**

- `ROWS`: height in rows. Omitted or `0`: fill the rest of the pane.
- `SUBMIT`: called as `SUBMIT ID TEXT` on `alt+enter` or `ctrl+enter`. Enter inserts a newline.

**Notes**

- Supports mouse placement, drag-select, word jumps, cut/copy/paste and undo. Up/Down at the first/last line move focus out of the widget.
- Tabs are converted to four spaces, and non-printable characters are dropped on insert.

**Example**

```bash
tui.textarea notes editor 0 "notes..." 0 save_notes
tui.on_change notes mark_dirty
```
