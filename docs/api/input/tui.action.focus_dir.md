### `tui.action.focus_dir`

```bash
tui.action.focus_dir up|down|left|right
```

Moves focus to the widget you would expect in that direction on screen.

**Notes**

- Left/right only consider widgets on the same screen row; up/down only widgets whose columns overlap the current one. When nothing is there, focus stays.
- With nothing focused, `down`/`right` focus the first widget and `up`/`left` the last.
