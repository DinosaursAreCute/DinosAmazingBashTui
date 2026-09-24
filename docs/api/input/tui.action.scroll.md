### `tui.action.scroll`

```bash
tui.action.scroll up|down|left|right [N]
```

Scrolls the target pane by `N` lines (up/down, default 3) or columns (left/right, default 5).

**Notes**

- Target: for mouse events the pane under the pointer; for keys the keyboard pane, else the pane under the pointer, else the focused widget's pane, else the first scrollable pane.
- The wheel over a textarea, list or table scrolls that widget instead.
- Merged repeats (`TUI_EVENT_COUNT`) multiply the distance.
