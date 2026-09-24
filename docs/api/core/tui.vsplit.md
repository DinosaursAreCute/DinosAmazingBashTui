### `tui.vsplit`

```bash
tui.vsplit PARENT NAME[:WEIGHT]...
```

Splits `PARENT` into stacked child panes, top to bottom.

**Parameters**

- `PARENT`: an existing pane.
- `NAME[:WEIGHT]`: one per child. `WEIGHT` is a positive integer share of the height. Default: `1`.

**Notes**

- Same rules as [`tui.hsplit`](/api/core/tui.hsplit.html): identifier-safe names, `single` border by default.

**Example**

```bash
tui.vsplit main header:1 body:5 status:1
```

**See also:** [`tui.hsplit`](/api/core/tui.hsplit.html)
