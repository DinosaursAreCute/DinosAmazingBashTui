# Plugins & hooks

`lib/plugin/tui_plugin.sh` - discovering, installing, enabling/disabling and reloading plugins, and the hook system they use to extend the framework. Guide: [../guide/plugins.md](../guide/plugins.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

## Plugins and hooks

Guide: [../guide/plugins.md](../guide/plugins.md). Files live under `~/.config/DABT/` (`TUI_HOME`): `plugins/` (`TUI_PLUGINS_DIR`) and `apps/<TUI_APP_NAME>/` (`TUI_APP_CONF`: `dabt.conf`, `keybinds.xml`, `settings.conf`, `app.meta`).

| Function | Parameters | Description |
|---|---|---|
| `tui.plugin.scan` | | Discover plugins in the built-in, app, user (`TUI_PLUGINS_DIR`) and `TUI_PLUGIN_DIRS` folders. |
| `tui.plugin.dir_add` | `DIR` | Add a folder to scan. |
| `tui.plugin.add` | `PATH [SOURCE]` | Register one plugin file or folder. → `TUI_PLUGIN_NAME` (or `TUI_PLUGIN_ERROR`). |
| `tui.plugin.install` | `PATH [--force]` | Copy a plugin into `TUI_PLUGINS_DIR` and register it (not enabled). |
| `tui.plugin.remove` | `NAME` | Disable and unregister; deletes it only if it is in the user folder. |
| `tui.plugin.enable` / `disable` / `toggle` / `reload` | `NAME` | Enable (requirements first) / disable (dependents first, everything it registered is undone) / flip / re-read the file. The choice is saved. |
| `tui.plugin.list` | | `NAME<TAB>STATE<TAB>VERSION<TAB>SOURCE<TAB>TITLE` per plugin. |
| `tui.plugin.info` | `NAME` | Text description. |
| `tui.plugin.get` | `NAME FIELD` | `title version description author requires state source file error`. |
| `tui.plugin.enabled` | `NAME` | Status 0 when enabled. |
| `tui.plugin.root` / `tui.plugin.dir` | `NAME` | The plugin's folder (or single file) / the folder its file is in. |
| `tui.plugin.files` | `NAME` | Every file of the plugin, one per line. |
| `tui.plugin.stats` | `NAME` | `key=value` lines: `files dirs bytes lines functions commands binds hooks timers ticks overlays providers`. |
| `tui.plugin.config` | `NAME KEY [VALUE]` | Get / set a plugin's saved setting (`plugin.NAME.KEY` in `dabt.conf`). |
| `tui.plugin.own` | `TYPE VALUE` | Add to what disabling undoes (`cmd bind hook every tick overlay provider run`). |
| `tui.hook.on` / `tui.hook.off` | `EVENT FN` | Register / remove a hook. |
| `tui.hook.fire` | `EVENT [ARG...]` | Call every handler; status 0 if one returned 0 (only the `key` event uses that: it consumes the key). |
| `tui.app.meta_get` | `KEY [DEFAULT]` | Read `app.meta`. |
| `tui.app.meta_set` | `KEY VALUE` | Write a key to `app.meta`. |
| `tui.app.dir` | | Print `TUI_APP_CONF`. |

Events: `init`, `ready`, `page FILE`, `resize ROWS COLS`, `key NAME`, `quit`, `exit`, `plugin_enabled NAME`, `plugin_disabled NAME`.
