### `tui.plugin.scan`

```bash
tui.plugin.scan
```

Discovers plugins (`NAME.plugin.sh` files and `NAME/plugin.sh` folders) and registers them, disabled.

**Notes**

- Folders, in order: `~/.config/DABT/plugins` (`TUI_PLUGINS_DIR`), the app's `plugins/`, `share/plugins` (when DABT is not installed), then each folder in `TUI_PLUGIN_DIRS` (colon-separated). Add more with [`tui.plugin.dir_add`](/api/plugin/tui.plugin.dir_add.html) first.
- When two folders hold a plugin of the same name, the first one wins; the other fails to register.
- [`tui.init`](/api/core/tui.init.html) runs it through [`tui.plugin.startup`](/api/plugin/tui.plugin.startup.html).
