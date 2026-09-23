# Config: persisted settings

`lib/config/tui_config.sh` - the small key/value store for framework settings, applied at `tui.init`. ← [API index](README.md) for the full module list and a task-oriented tour with examples.

## Persisted config

Small key/value store for framework settings (`~/.config/DABT/apps/<app>/dabt.conf`), applied at `tui.init`. Known keys: `theme`, `defaults.off`, `input.retain`, `input.coalesce`, `confirm.quit`, `notify.position`, `notify.seconds`.

| Function | Parameters | Description |
|---|---|---|
| `tui.config.get` | `KEY [DEFAULT]` | Print a value. |
| `tui.config.set` | `KEY VALUE` | Set and save. |
| `tui.config.unset` | `KEY` | Remove and save. |
| `tui.config.load` / `tui.config.save` | | Read / write the file. |
| `tui.config.apply` | | Apply the loaded settings to the running framework. |
