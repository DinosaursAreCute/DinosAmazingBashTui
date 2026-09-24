### `tui.bind.defaults`

```bash
tui.bind.defaults [FILE]
```

Reloads the default bindings, replacing the current defaults.

**Parameters**

- `FILE`: default `$TUI_DEFAULTS_DIR/keybinds.xml`: `~/.config/DABT/defaults/keybinds.xml` when installed, else `share/defaults/keybinds.xml`.

**Returns:** `1` when `FILE` can't be read; the app then has no defaults.

**Notes**

- One `<bind key="…" action="…" group="…" [desc="…"] [always="true"]/>` per line. Bindings without `group` go into `misc`.
