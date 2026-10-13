### `tui.md.forward`

```bash
tui.md.forward PANE
```

Goes forward in `PANE`'s document history after [`tui.md.back`](tui.md.back.md): the document (and scroll position) the last back stepped over. Following a link starts a new trail and drops what was ahead.

**Notes**

- Returns 1 when there is nothing ahead.
- Default keys: `alt+right` (while the pane has the keyboard) and the forward thumb button of the mouse.

**Example**

```bash
tui.bind alt+n "tui.md.forward docs" --always
```
