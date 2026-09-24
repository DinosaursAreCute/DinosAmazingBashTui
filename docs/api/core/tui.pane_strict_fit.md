### `tui.pane_strict_fit`

```bash
tui.pane_strict_fit PANE true|false
```

Turns the automatic content-fit check of a leaf pane on (default) or off.

**Notes**

- With the check on, a pane whose widgets need more room than it has shows the `min space` notice. `false` falls back to the explicit [`tui.pane_minsize`](/api/core/tui.pane_minsize.html) only; use it for panes where clipping is fine (tab headers do this).
