### `tui.restyle`

```bash
tui.restyle ID CLASS
```

Gives a widget or pane the look of a theme class and redraws just it: the widget, or the pane's border, title and widgets. What the id had before is cleared first, so a `:hover` the old class had does not linger.

**Returns:** `1` for an unknown id or an empty class.

**Notes**

- [`tui.class`](/api/style/tui.class.html) only bakes the style; without a redraw the old look stays on screen until something repaints it.

**Example**

```bash
tui.restyle health_box tile_err      # the border and title turn red
```
