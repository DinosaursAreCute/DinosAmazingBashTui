### `tui.set`

```bash
tui.set ID VALUE
```

Sets a widget's value without redrawing it.

**Notes**

- Use it to prepare several widgets before one repaint, or before the first render. While the app runs, use [`tui.update`](/api/widgets/tui.update.html) so the change is visible.
- Checkbox values must be `0` or `1`.
