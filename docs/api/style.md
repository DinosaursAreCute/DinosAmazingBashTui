# Style: themes

`lib/style/tui_style.sh` - resolves `theme.css` (`.class`, `:focus`, `:hover`, `:border`, `:title`) to fg/bg/mods per pane and widget. Guide: [../guide/markup.md](../guide/markup.md#theming). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

## Styling and themes

STATE = `normal` (default) `focus border title hover checked unchecked` (the last two apply to checkboxes); a state without rules falls back to normal.

| Function | Parameters | Description |
|---|---|---|
| `tui.load_theme` | `FILE` | Load a `theme.css` (memoized by mtime). |
| `tui.class` | `ID CLASS` | Apply `.CLASS` (+ `:focus/:border/:title/:hover`) to a widget or pane. |
| `tui.style` | `ID FG BG MODS [STATE]` | Low-level style setter (FG/BG: color name or `#rrggbb`; MODS: `bold dim italic underline reverse ...`). |
| `tui.ansi` | `ID [STATE]` | Print the ANSI prefix of an id's style. |
| `tui.class.ansi` | `CLASS [STATE]` | Same, straight from a theme class. |
| `tui.paint` | `ID TEXT [STATE]` | Print TEXT wrapped in the id's style + reset. |
| `tui.class.paint` | `CLASS TEXT [STATE]` | Same for a class. |
| `tui.style.sgr` | `ID [STATE]` | Fork-free → `TUI_SGR TUI_FG TUI_BG`. |
| `tui.class.style` | `CLASS [STATE]` | → `TUI_FG TUI_BG TUI_MODS`. |
| `tui.class.sgr` | `CLASS [STATE]` | → `TUI_SGR` (+ the three above), fork-free. |
| `tui.class.names` | | → `TUI_CLASSES` array (sorted). |
| `tui.theme.set` | `FILE` | Layer FILE over every page's own theme, app-wide; reloads the page. |
| `tui.theme.clear` | | Remove the overlay. |
| `tui.theme.current` | | Print the overlay file. |
| `tui.theme.reload` | | Reload the current page. |
| `tui.cache.theme_clear` | | Forget every memoized stylesheet. |
