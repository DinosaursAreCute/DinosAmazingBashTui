### `tui.class.sgr`

```bash
tui.class.sgr CLASS [STATE]
```

Resolves a theme class into an escape prefix, without a subshell.

**Sets:** `TUI_SGR`, plus `TUI_FG`, `TUI_BG`, `TUI_MODS`.

**Example**

```bash
tui.class.sgr nav_link focus
printf '%s text%s' "$TUI_SGR" "$TUI_RESET"
```
