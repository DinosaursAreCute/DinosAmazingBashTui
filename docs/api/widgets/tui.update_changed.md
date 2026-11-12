### `tui.update_changed`

```bash
tui.update_changed ID TEXT
```

Sets a widget's value and redraws it like [`tui.update`](/api/widgets/tui.update.html), but returns without drawing when the widget already holds `TEXT`.

**Notes**

- Fork-free. Use it in `tui.every` callbacks and polls that recompute a value on each run: an unchanged value costs one comparison, not a draw and a flush.
- For a pane, [`tui.set_text`](/api/core/tui.set_text.html) already skips unchanged text.
- Compares against the stored value, so a widget that was changed with `tui.set` (no redraw) to `TEXT` is not redrawn either. Use `tui.update` when the screen may be stale.

**Example**

```bash
clock_tick() { printf -v now '%(%H:%M)T' -1; tui.update_changed lbl_clock "$now"; }
tui.every 1 clock_tick
```
