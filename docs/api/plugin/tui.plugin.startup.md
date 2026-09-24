### `tui.plugin.startup`

```bash
tui.plugin.startup
```

Scans for plugins (once) and enables each one whose saved state, or `# default:` when never set, is on. Called by `tui.init`.

**Notes**

- Set `TUI_NO_PLUGINS=1` to skip plugins entirely.
- A plugin that fails prints `plugin NAME: REASON` on stderr and stays disabled.
