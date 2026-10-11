### `tui.md.copy`

```bash
tui.md.copy PANE [doc|section|rendered]
```

Copies part of the document shown in `PANE` to the clipboard with [`tui.clipboard.copy`](/api/input/tui.clipboard.copy.html), and notifies.

**Parameters**

- `doc|section|rendered`: `doc` copies the document source, `section` the source of the section at the top of the view (default), `rendered` the rendered plain text.

**Example**

```bash
tui.md.copy docs doc
```
