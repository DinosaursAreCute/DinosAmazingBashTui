### `tui.addon.dir`

```bash
tui.addon.dir DIR
```

Adds a directory whose `*.xml` files hold [addons](/guide/markup.html#addons), so a plugin can ship its own page changes. The app's own `TUI_APP_CONF/addons` is always read.

**Parameters**

- `DIR`: a directory path. A directory that does not exist is ignored.

**Notes**

- Files are read in name order; `priority` inside each addon decides the order they are applied in. An empty file is a switched-off addon.
- Called from a plugin's `on_enable`, the folder is removed again when the plugin is disabled ([`tui.addon.undir`](/api/core/tui.addon.undir.html)).
- Pages already built are not changed. Call [`tui.page.refresh`](/api/core/tui.page.refresh.html) to apply the folder to the page on screen.

**Example**

```bash
plugin.stats.on_enable() {
    tui.addon.dir "$(tui.plugin.dir stats)/addons"
    tui.page.refresh
}
```

**See also:** [`tui.addon.undir`](/api/core/tui.addon.undir.html), [`tui.page.refresh`](/api/core/tui.page.refresh.html)
