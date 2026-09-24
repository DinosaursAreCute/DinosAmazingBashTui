### `tui.pane_title`

```bash
tui.pane_title PANE TEXT
```

Sets the title drawn in the pane's top border.

**Notes**

- Not drawn when the pane has no border.
- While the app runs, call [`tui.relayout`](/api/core/tui.relayout.html) `PANE` to show the change.
