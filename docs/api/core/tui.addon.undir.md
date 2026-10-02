### `tui.addon.undir`

```bash
tui.addon.undir DIR
```

Forgets a folder that was registered with [`tui.addon.dir`](/api/core/tui.addon.dir.html). Its addons stop applying to pages loaded from now on.

**Notes**

- A plugin does not need to call it: the folder a plugin registered in `on_enable` is removed when the plugin is disabled.
- The screen does not change by itself; call [`tui.page.refresh`](/api/core/tui.page.refresh.html) to take the addons off the page that is showing.

**See also:** [`tui.addon.dir`](/api/core/tui.addon.dir.html)
