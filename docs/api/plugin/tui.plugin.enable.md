### `tui.plugin.enable`

```bash
tui.plugin.enable NAME [--no-save]
```

Enables a plugin: enables its requirements first, sources its file and runs `plugin.NAME.on_enable`.

**Returns:** `1` when the plugin is unknown, a requirement fails, the requirements are circular, or sourcing or `on_enable` fails. The reason is in `TUI_PLUGIN_ERROR`.

**Notes**

- Commands, bindings, hooks, timers, tick listeners, overlays and palette providers registered while it loads are recorded, so disabling undoes them.
- The state is saved as config `plugin.NAME.enabled=1` unless `--no-save` is given.
- Fires the `plugin_enabled` hook.
- On failure, what the plugin registered so far is undone and its state becomes `error`.
