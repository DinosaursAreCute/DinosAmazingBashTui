### `tui.theme.pick`

```bash
tui.theme.pick [NAME]
```

Applies the theme `NAME` from [`tui.theme.list`](/api/style/tui.theme.list.html) to every page and remembers it for the next start. Without `NAME` it removes the overlay (page default).

**Returns:** `1` when no theme is called `NAME`.

**Notes**

- Same as picking a theme on the Settings page or in the command palette: [`tui.config.set`](/api/config/tui.config.set.html) `theme FILE`, then [`tui.theme.set`](/api/style/tui.theme.set.html), which reloads the current page.

**Example**

```bash
tui.theme.pick nord
tui.theme.pick          # back to the page default
```

**See also:** [`tui.theme.set`](/api/style/tui.theme.set.html) (this run only)
