### `tui.pane.focus`

```bash
tui.pane.focus PANE
```

Makes `PANE` the keyboard pane: the target of scroll keys, drawn with a highlighted border.

**Parameters**

- `PANE`: pane id, or `""` to clear.

**Notes**

- Focusing a widget also moves pane focus to the widget's pane.
- Only the two affected borders are redrawn.

**See also:** [`tui.get.pane_focus`](/api/core/tui.get.pane_focus.html), [`tui.action.focus_pane`](/api/input/tui.action.focus_pane.html)
