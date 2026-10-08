### `tui.pane_title`

```bash
tui.pane_title PANE TEXT
```

Sets the title drawn in the pane's top border.

**Notes**

- A `^` marks the next character as an accent, drawn in the `title_key` theme class (bold red without a rule): `"^1cpu"`, `"^menu"`. `^^` is a literal caret.
- Not drawn when the pane has no border.
- While the app runs, a changed title repaints just the pane's border; no [`tui.relayout`](/api/core/tui.relayout.html) is needed. An unchanged title costs nothing, so it is safe to call from a timer.
