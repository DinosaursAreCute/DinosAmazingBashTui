### `tui.action.resize_mode`

```bash
tui.action.resize_mode
```

Toggles keyboard resize mode (default key `alt+r`) on the focused pane's nearest resizable ancestor; when there is none (focus in a pane without a resizable ancestor, nothing focused) it takes the first resizable pane of the page in layout order.

**Returns:** `1` when the page has no resizable pane; a `Nothing resizable here` toast is shown once.

**Notes**

- In the mode arrows resize by 1, shift+arrows by 5, Enter or Esc leave. The mode is the global `_TUI_RESIZE_PANE`; the footer shows `alt+r Resize` while the mode can start and `arrows Resize | Enter Done` in the mode. While it lasts the target's border is drawn with the `.resize_handle:hover` style and its title carries a ` [resize]` tag; both go away on leaving. The key is a default bind (group `resize`): an installed copy of the defaults from an older version lacks it, so a checkout newer than `$TUI_HOME/install.meta` uses its own `share/defaults`.

**See also:** [`tui.pane_resizable`](/api/core/tui.pane_resizable.html)
