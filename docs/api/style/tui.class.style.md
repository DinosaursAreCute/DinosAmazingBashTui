### `tui.class.style`

```bash
tui.class.style CLASS [STATE]
```

Resolves a theme class into variables, without a subshell. Sets `TUI_FG`, `TUI_BG`, `TUI_MODS`.

**Notes**

- A state the class does not define falls back to the plain class.
