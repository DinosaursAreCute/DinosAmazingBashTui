### `tui.apps.install`

```bash
tui.apps.install SRC [--force] [--name NAME] [--entry REL]
```

Installs a DABT application from a folder or a git URL (`URL#ref` for a branch or tag). `dabt app install` calls it.

**Options**

- `--force`: install a folder without a `.dabt.metadata` file (then `--name` and `--entry` are needed), or replace an installed app.
- `--name NAME`, `--entry REL`: override or supply the name and the start script.

**Notes**

- The app's `.dabt.metadata` must name `name` and `entry`; `min_dabt`/`max_dabt` are checked against this version.
- The app goes to `~/.config/DABT/apps/NAME`, or `~/.local/share/dabt-apps/NAME` with `own_dir=yes`, and is recorded in `$TUI_HOME/apps.list`.
- Runs the app's `install_hook`, if any. A failing hook only warns.
