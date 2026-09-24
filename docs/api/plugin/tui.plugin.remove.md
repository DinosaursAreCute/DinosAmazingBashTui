### `tui.plugin.remove`

```bash
tui.plugin.remove NAME
```

Disables a plugin, runs its `plugin.NAME.on_remove`, unregisters it and forgets its saved state.

**Returns:** `1` for an unknown plugin.

**Notes**

- Files are deleted only for user plugins inside `~/.config/DABT/plugins`. Built-in and app plugins are only unregistered and come back on the next scan.
