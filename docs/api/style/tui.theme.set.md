### `tui.theme.set`

```bash
tui.theme.set FILE
```

Sets an app-wide stylesheet that is layered over every page's own theme, and reloads the current page.

**Notes**

- Lasts for this run only. To keep it across restarts, also `tui.config.set theme FILE` (the Settings page does both).
- The reload runs the page's `on_visit` again.

**Example**

```bash
tui.theme.set "$APP/themes/ocean.css"
```

**See also:** [`tui.theme.clear`](/api/style/tui.theme.clear.html)
