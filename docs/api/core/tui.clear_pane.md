### `tui.clear_pane`

```bash
tui.clear_pane PANE
```

Blanks the pane's content rectangle on screen.

**Notes**

- Writes to the terminal directly and does not change the pane's content; the next repaint draws it again. Use [`tui.output_clear`](/api/core/tui.output_clear.html) to empty the content.
