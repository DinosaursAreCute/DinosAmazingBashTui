### `tui.factory.clear`

```bash
tui.factory.clear NS
```

Removes every widget and pane created under namespace `NS` and turns its grid parents back into empty leaf panes.

**Notes**

- Safe on a namespace that is empty or already cleared.
- Does not repaint. Call [`tui.relayout`](/api/core/tui.relayout.html) after rebuilding.
- Everything is also dropped on page change.
