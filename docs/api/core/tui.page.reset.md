### `tui.page.reset`

```bash
tui.page.reset [PAGE]
```

Forgets the stored state of a page and puts the current page back to its first-build state.

**Parameters**

- `PAGE`: optional page basename; default the current page. Another page only loses its stored state.

**Notes**

- Every kept widget and pane returns to the value, selection, scroll and collapsed state it had when the page was first built; every resized split returns to its weights before the first resize. Then the page is laid out again, `on_resize` callbacks run and a repaint is requested.
- Bound to `alt+shift+r` (`tui.action.page_reset`).

**See also:** [`tui.page.reset_field`](/api/core/tui.page.reset_field.html), [`tui.page.reset_all`](/api/core/tui.page.reset_all.html), [`tui.page.resettable`](/api/core/tui.page.resettable.html)
