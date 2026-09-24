### `tui.pane_valign`

```bash
tui.pane_valign PANE top|middle|bottom
```

Sets the default vertical anchor for widgets in the pane. Default: `top`.

**Notes**

- A widget's `ROW` counts from the anchor: with `bottom`, row `0` is the last line and higher rows go up.
- A widget's own [`tui.valign`](/api/widgets/tui.valign.html) wins.
