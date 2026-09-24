# Config: persisted settings

`lib/config/tui_config.sh` - the small key/value store for framework settings, applied at `tui.init`. ← [API index](README.md) for the full module list and a task-oriented tour with examples.

## Persisted config

Settings live in `~/.config/DABT/apps/<TUI_APP_NAME>/dabt.conf` as `key=value` lines (set `TUI_CONFIG_FILE` before sourcing `tui.sh` to use another file). Any key can be stored; apps may keep their own keys here too. The framework reads these:

| Key | Values | Read |
|---|---|---|
| `theme` | path to a `.css` overlay | at start (the Settings page writes it; [`tui.theme.set`](style/tui.theme.set.md) alone does not) |
| `defaults.off` | space-separated default-bind groups | at start |
| `input.retain` | `1` / `0` | at start |
| `input.coalesce` | `1` / `0` | at start |
| `notify.position` | see [`tui.notify.position`](chrome/tui.notify.position.md) | at start |
| `notify.seconds` | seconds, `0` = sticky | at start |
| `confirm.quit` | `1` / `0` | at every quit |
| `plugin.NAME.enabled`, `plugin.NAME.KEY` | plugin state and settings | by the plugin system |

Functions return `0` unless stated.

<!-- api: tui.config.get tui.config.set tui.config.unset tui.config.keys tui.config.load tui.config.save tui.config.apply -->

| Function | Summary |
|---|---|
| [`tui.config.get`](config/tui.config.get.md) | Prints the saved value of a setting. |
| [`tui.config.set`](config/tui.config.set.md) | Stores a setting and writes the config file immediately. |
| [`tui.config.unset`](config/tui.config.unset.md) | Removes a setting and writes the config file immediately. |
| [`tui.config.keys`](config/tui.config.keys.md) | Prints every stored key, sorted, one per line. |
| [`tui.config.load`](config/tui.config.load.md) | Replaces the in-memory store with the contents of the config file. |
| [`tui.config.save`](config/tui.config.save.md) | Writes the in-memory store to the config file. |
| [`tui.config.apply`](config/tui.config.apply.md) | Applies the stored framework settings to the running framework. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative config/tui.config.get.md %}

{% include_relative config/tui.config.set.md %}

{% include_relative config/tui.config.unset.md %}

{% include_relative config/tui.config.keys.md %}

{% include_relative config/tui.config.load.md %}

{% include_relative config/tui.config.save.md %}

{% include_relative config/tui.config.apply.md %}

</div>

<!-- /api -->
