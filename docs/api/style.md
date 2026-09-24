# Style: themes

`lib/style/tui_style.sh`, `lib/tui_api.sh` - resolves `theme.css` (`.class`, `:focus`, `:hover`, `:border`, `:title`, `:checked`, `:unchecked`) to fg/bg/mods per pane and widget. Guide: [../guide/markup.md](../guide/markup.md#theming). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

`STATE` is one of `normal` (default), `focus`, `border`, `title`, `hover`, `checked`, `unchecked` (the last two for checkboxes); a state without rules falls back to `normal`. Colors are `black red green yellow blue magenta cyan white default`, `br_black` ... `br_white`, or `#rrggbb`. Functions return `0` unless their entry says otherwise.

Functions that print (`tui.ansi`, `tui.paint`, ...) need a subshell when captured. In code that runs every frame use the ones that set variables (`tui.style.sgr`, `tui.class.sgr`, `tui.class.style`, `tui.class.names`).

## Styling and themes

<!-- api: tui.load_theme tui.class tui.style tui.ansi tui.class.ansi tui.paint tui.class.paint tui.style.sgr tui.class.style tui.class.sgr tui.class.names tui.cache.theme_clear -->

| Function | Summary |
|---|---|
| [`tui.load_theme`](style/tui.load_theme.md) | Loads a stylesheet into the class table. `<theme src="…"/>` calls it. |
| [`tui.class`](style/tui.class.md) | Applies a theme class to a widget or pane: its normal rules and every pseudo-state it defines (`:focus`, `:border`, `:title`, `:hover`, `:checked`, `:unchecked`). |
| [`tui.style`](style/tui.style.md) | Sets the style of a widget or pane directly, without a theme class. |
| [`tui.ansi`](style/tui.ansi.md) | Prints the ANSI escape prefix of a widget or pane style (no reset). A state without rules falls back to `normal`. |
| [`tui.class.ansi`](style/tui.class.ansi.md) | Prints the ANSI escape prefix of a theme class, without a widget. |
| [`tui.paint`](style/tui.paint.md) | Prints `TEXT` in the style of a widget or pane, followed by a reset. No newline. |
| [`tui.class.paint`](style/tui.class.paint.md) | Prints `TEXT` in the style of a theme class, followed by a reset. No newline. |
| [`tui.style.sgr`](style/tui.style.sgr.md) | Resolves the style of a widget or pane into variables, without a subshell. |
| [`tui.class.style`](style/tui.class.style.md) | Resolves a theme class into variables, without a subshell. Sets `TUI_FG`, `TUI_BG`, `TUI_MODS`. |
| [`tui.class.sgr`](style/tui.class.sgr.md) | Resolves a theme class into an escape prefix, without a subshell. |
| [`tui.class.names`](style/tui.class.names.md) | Stores every class and pseudo-state key of the loaded theme, sorted, in the array `TUI_CLASSES`. Fork-free. |
| [`tui.cache.theme_clear`](style/tui.cache.theme_clear.md) | Forgets every memoized stylesheet, so the next load parses the files again. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative style/tui.load_theme.md %}

{% include_relative style/tui.class.md %}

{% include_relative style/tui.style.md %}

{% include_relative style/tui.ansi.md %}

{% include_relative style/tui.class.ansi.md %}

{% include_relative style/tui.paint.md %}

{% include_relative style/tui.class.paint.md %}

{% include_relative style/tui.style.sgr.md %}

{% include_relative style/tui.class.style.md %}

{% include_relative style/tui.class.sgr.md %}

{% include_relative style/tui.class.names.md %}

{% include_relative style/tui.cache.theme_clear.md %}

</div>

<!-- /api -->

## App-wide theme overlay

<!-- api: tui.theme.set tui.theme.clear tui.theme.current tui.theme.reload -->

| Function | Summary |
|---|---|
| [`tui.theme.set`](style/tui.theme.set.md) | Sets an app-wide stylesheet that is layered over every page's own theme, and reloads the current page. |
| [`tui.theme.clear`](style/tui.theme.clear.md) | Removes the app-wide stylesheet and reloads the current page. |
| [`tui.theme.current`](style/tui.theme.current.md) | Prints the path of the app-wide stylesheet (empty when none). |
| [`tui.theme.reload`](style/tui.theme.reload.md) | Reloads the current page, keeping focus and cursor when the focused widget still exists. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative style/tui.theme.set.md %}

{% include_relative style/tui.theme.clear.md %}

{% include_relative style/tui.theme.current.md %}

{% include_relative style/tui.theme.reload.md %}

</div>

<!-- /api -->
