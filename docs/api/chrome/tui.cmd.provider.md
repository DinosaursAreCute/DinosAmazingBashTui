### `tui.cmd.provider`

```bash
tui.cmd.provider FN
```

Registers a function that runs every time the palette opens and adds commands that depend on current state.

**Notes**

- Commands added inside `FN` are removed and rebuilt on every open, so they never go stale.
- Registering the same `FN` twice is a no-op.

**Example**

```bash
theme_commands() {
    local f
    for f in "$APP"/themes/*.css; do
        tui.cmd.add "theme:${f##*/}" "Theme: ${f##*/}" "tui.theme.set $f" --group Themes
    done
}
tui.cmd.provider theme_commands
```
