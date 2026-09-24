### `tui.plugin.disable`

```bash
tui.plugin.disable NAME [--no-save]
```

Disables a plugin: disables plugins that require it first, runs `plugin.NAME.on_disable`, then undoes everything it registered, newest first.

**Returns:** `1` for an unknown plugin.

**Notes**

- The state is saved as `plugin.NAME.enabled=0` unless `--no-save` is given.
- Its functions stay defined until it is removed or reloaded.
- Fires the `plugin_disabled` hook.
