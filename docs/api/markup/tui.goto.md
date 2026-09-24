### `tui.goto`

```bash
tui.goto FILE
```

Switches to another page: clears the current UI, loads `FILE` (from the page cache when valid) and repaints in one frame.

**Parameters**

- `FILE`: relative paths resolve against the current page's folder.

**Notes**

- Everything page-scoped is dropped: panes, widgets, timers, watches, `tui.exec` instances, the modal, the footer, `--page` bindings. Tick listeners from [`tui.tick.add`](/api/core/tui.tick.add.html) and overlays are kept.
- The previous page is pushed onto the history for [`tui.action.back`](/api/input/tui.action.back.html) (up to 30 entries).
- Reloading the same page keeps the focused widget and cursor when that widget still exists.
- The page's `on_visit` function runs on every visit, also when the page is replayed from the cache.
- Fires the `page` hook with the resolved path.

**Example**

```bash
open_settings() { tui.goto settings.xml; }
```
