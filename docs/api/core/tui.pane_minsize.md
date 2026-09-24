### `tui.pane_minsize`

```bash
tui.pane_minsize PANE [MIN_W] [MIN_H]
```

Sets the smallest size at which the pane shows its content. Below it, the pane shows a `min space = WxH` notice instead.

**Parameters**

- `MIN_W`, `MIN_H`: columns and rows. Empty leaves that value unchanged.

**Notes**

- Leaf panes also get an automatic minimum from their content unless [`tui.pane_strict_fit`](/api/core/tui.pane_strict_fit.html) is `false`.

**See also:** [`tui.pane_maxsize`](/api/core/tui.pane_maxsize.html)
