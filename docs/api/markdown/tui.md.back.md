### `tui.md.back`

```bash
tui.md.back PANE
```

Returns `PANE` to the document and scroll position before the last followed link or anchor.

**Returns:** `1` when there is nothing to go back to.

**Notes**

- Each pane keeps its own stack.

**Example**

```bash
tui.md.back docs
```
