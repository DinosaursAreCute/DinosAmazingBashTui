### `tui.pane_scroll`

```bash
tui.pane_scroll PANE none|v|h|both
```

Enables scrolling of the pane's output and resets its scroll position to the top left.

**Notes**

- Scrolling applies to [`tui.output`](/api/core/tui.output.html) content: wheel, `j`/`k`, page keys and a draggable scrollbar.
- Calling it again, even with the same mode, jumps back to the top.

**See also:** [`tui.get.scroll`](/api/core/tui.get.scroll.html), [`tui.action.scroll`](/api/input/tui.action.scroll.html)
