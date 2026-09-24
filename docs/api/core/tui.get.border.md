### `tui.get.border`

```bash
tui.get.border PANE
```

Prints the border actually drawn: `single`, `double`, `heavy` or `none`. Returns `1` for an unknown pane.

**Notes**

- This is the effective style: a border that does not fit, or an unset border on a parent pane, prints `none`.
