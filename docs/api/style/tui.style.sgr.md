### `tui.style.sgr`

```bash
tui.style.sgr ID [STATE]
```

Resolves the style of a widget or pane into variables, without a subshell.

**Sets:** `TUI_SGR` (escape prefix), `TUI_FG`, `TUI_BG`. `TUI_RESET` always holds `\e[0m`.

**Example**

```bash
tui.style.sgr log title
tui.output_append log "${TUI_SGR}== section ==${TUI_RESET}"
```
