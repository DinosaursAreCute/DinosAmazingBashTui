# Plugins & hooks

`lib/plugin/tui_plugin.sh`, `lib/tui_home.sh` - discovering, installing, enabling/disabling and reloading plugins, the hook system they use to extend the framework, and the per-app metadata file. Guide: [../guide/plugins.md](../guide/plugins.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

Files live under `~/.config/DABT/` (`TUI_HOME`): `plugins/` (`TUI_PLUGINS_DIR`) and `apps/<TUI_APP_NAME>/` (`TUI_APP_CONF`: `dabt.conf`, `keybinds.xml`, `settings.conf`, `app.meta`, `logs/`). A plugin is a `NAME.plugin.sh` file or a `NAME/plugin.sh` folder; it defines `plugin.NAME.on_enable`, and optionally `on_disable` and `on_remove`. Plugins are trusted code: they run in the app's shell with its permissions. Functions return `0` unless their entry says otherwise.

## Plugins

<!-- api: tui.plugin.scan tui.plugin.dir_add tui.plugin.add tui.plugin.install tui.plugin.remove tui.plugin.enable tui.plugin.disable tui.plugin.toggle tui.plugin.reload tui.plugin.startup tui.plugin.list tui.plugin.info tui.plugin.get tui.plugin.enabled tui.plugin.root tui.plugin.dir tui.plugin.files tui.plugin.stats tui.plugin.config tui.plugin.own -->

| Function | Summary |
|---|---|
| [`tui.plugin.scan`](plugin/tui.plugin.scan.md) | Discovers plugins (`NAME.plugin.sh` files and `NAME/plugin.sh` folders) and registers them, disabled. |
| [`tui.plugin.dir_add`](plugin/tui.plugin.dir_add.md) | Adds a folder for [`tui.plugin.scan`](/api/plugin/tui.plugin.scan.html) to search. Adding a folder twice is a no-op. |
| [`tui.plugin.add`](plugin/tui.plugin.add.md) | Registers one plugin file or folder, disabled. |
| [`tui.plugin.install`](plugin/tui.plugin.install.md) | Security-scans a plugin, copies it into `~/.config/DABT/plugins` and registers it, disabled. |
| [`tui.plugin.remove`](plugin/tui.plugin.remove.md) | Disables a plugin, runs its `plugin.NAME.on_remove`, unregisters it and forgets its saved state. |
| [`tui.plugin.enable`](plugin/tui.plugin.enable.md) | Enables a plugin: enables its requirements first, sources its file and runs `plugin.NAME.on_enable`. |
| [`tui.plugin.disable`](plugin/tui.plugin.disable.md) | Disables a plugin: disables plugins that require it first, runs `plugin.NAME.on_disable`, then undoes everything it registered, newest first. |
| [`tui.plugin.toggle`](plugin/tui.plugin.toggle.md) | Disables an enabled plugin, or enables any other. The choice is saved. |
| [`tui.plugin.reload`](plugin/tui.plugin.reload.md) | Re-reads a plugin after its file changed: disables it, drops its `plugin.NAME.*` functions, re-reads the metadata, and enables it again if it was enabled. Returns `1` for an unknown plugin. |
| [`tui.plugin.startup`](plugin/tui.plugin.startup.md) | Scans for plugins (once) and enables each one whose saved state, or `# default:` when never set, is on. Called by `tui.init`. |
| [`tui.plugin.list`](plugin/tui.plugin.list.md) | Prints every registered plugin in discovery order. |
| [`tui.plugin.info`](plugin/tui.plugin.info.md) | Prints a readable description: title, version, description, id, state (with the error), source, file, author and requirements. Returns `1` for an unknown plugin. |
| [`tui.plugin.get`](plugin/tui.plugin.get.md) | Prints one field of a plugin: `title`, `version`, `description`, `author`, `requires`, `state`, `source`, `file` or `error`. Returns `1` for any other field. |
| [`tui.plugin.enabled`](plugin/tui.plugin.enabled.md) | Returns `0` when the plugin is enabled, else `1`. |
| [`tui.plugin.root`](plugin/tui.plugin.root.md) | Prints the plugin folder for a folder plugin, or the file for a single-file plugin. Returns `1` for an unknown plugin. |
| [`tui.plugin.dir`](plugin/tui.plugin.dir.md) | Prints the folder that contains the plugin file. Use it to find assets shipped next to the plugin. Returns `1` for an unknown plugin. |
| [`tui.plugin.files`](plugin/tui.plugin.files.md) | Prints every file of the plugin, one per line (recursive for a folder plugin). Returns `1` for an unknown plugin. |
| [`tui.plugin.stats`](plugin/tui.plugin.stats.md) | Prints size figures and what the plugin currently has registered. |
| [`tui.plugin.config`](plugin/tui.plugin.config.md) | Reads or writes a plugin's own saved setting, stored as `plugin.NAME.KEY` in `dabt.conf`. |
| [`tui.plugin.own`](plugin/tui.plugin.own.md) | Adds something to what disabling the current plugin undoes. Only has an effect while a plugin is being enabled. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative plugin/tui.plugin.scan.md %}

{% include_relative plugin/tui.plugin.dir_add.md %}

{% include_relative plugin/tui.plugin.add.md %}

{% include_relative plugin/tui.plugin.install.md %}

{% include_relative plugin/tui.plugin.remove.md %}

{% include_relative plugin/tui.plugin.enable.md %}

{% include_relative plugin/tui.plugin.disable.md %}

{% include_relative plugin/tui.plugin.toggle.md %}

{% include_relative plugin/tui.plugin.reload.md %}

{% include_relative plugin/tui.plugin.startup.md %}

{% include_relative plugin/tui.plugin.list.md %}

{% include_relative plugin/tui.plugin.info.md %}

{% include_relative plugin/tui.plugin.get.md %}

{% include_relative plugin/tui.plugin.enabled.md %}

{% include_relative plugin/tui.plugin.root.md %}

{% include_relative plugin/tui.plugin.dir.md %}

{% include_relative plugin/tui.plugin.files.md %}

{% include_relative plugin/tui.plugin.stats.md %}

{% include_relative plugin/tui.plugin.config.md %}

{% include_relative plugin/tui.plugin.own.md %}

</div>

<!-- /api -->

## Hooks

<!-- api: tui.hook.on tui.hook.off tui.hook.fire -->

| Function | Summary |
|---|---|
| [`tui.hook.on`](plugin/tui.hook.on.md) | Registers `FN` to run when the framework fires `EVENT`. |
| [`tui.hook.off`](plugin/tui.hook.off.md) | Removes a hook handler. |
| [`tui.hook.fire`](plugin/tui.hook.fire.md) | Calls every handler of `EVENT` with the arguments. Returns `0` when at least one handler returned `0`, else `1`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative plugin/tui.hook.on.md %}

{% include_relative plugin/tui.hook.off.md %}

{% include_relative plugin/tui.hook.fire.md %}

</div>

<!-- /api -->

## App metadata

<!-- api: tui.app.meta_get tui.app.meta_set tui.app.dir -->

| Function | Summary |
|---|---|
| [`tui.app.meta_get`](plugin/tui.app.meta_get.md) | Prints a value from the app's `app.meta` (no newline), or `DEFAULT`. |
| [`tui.app.meta_set`](plugin/tui.app.meta_set.md) | Stores a key in the app's `app.meta` and writes the file. |
| [`tui.app.dir`](plugin/tui.app.dir.md) | Prints the app's config folder, `TUI_APP_CONF` (`~/.config/DABT/apps/<TUI_APP_NAME>`). |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative plugin/tui.app.meta_get.md %}

{% include_relative plugin/tui.app.meta_set.md %}

{% include_relative plugin/tui.app.dir.md %}

</div>

<!-- /api -->
