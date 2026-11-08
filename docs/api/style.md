# Style: themes

`lib/style/tui_style.sh`, `lib/tui_api.sh` - resolves `theme.css` (`.class`, `:focus`, `:hover`, `:border`, `:title`, `:checked`, `:unchecked`) to fg/bg/mods per pane and widget. Guide: [../guide/markup.md](../guide/markup.md#theming). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

`STATE` is one of `normal` (default), `focus`, `border`, `title`, `hover`, `checked`, `unchecked` (the last two for checkboxes); a state without rules falls back to `normal`. Colors are `black red green yellow blue magenta cyan white default`, `br_black` ... `br_white`, or `#rrggbb`. Functions return `0` unless their entry says otherwise.

Functions that print (`tui.ansi`, `tui.paint`, ...) need a subshell when captured. In code that runs every frame use the ones that set variables (`tui.style.sgr`, `tui.class.sgr`, `tui.class.style`, `tui.class.names`).

## Styling and themes

<!-- api: tui.load_theme tui.class tui.style tui.ansi tui.class.ansi tui.paint tui.class.paint tui.paint.reset tui.style.sgr tui.class.style tui.class.sgr tui.class.names tui.glyph.get tui.glyph.set tui.glyph.user tui.glyph.available tui.variant.default tui.variant.list tui.cache.theme_clear -->

| Function | Summary |
|---|---|
| [`tui.load_theme`](style/tui.load_theme.md) | Loads a stylesheet into the class table. `<theme src="…"/>` calls it. |
| [`tui.class`](style/tui.class.md) | Applies a theme class to a widget or pane: its normal rules and every pseudo-state it defines (`:focus`, `:border`, `:title`, `:hover`, `:checked`, `:unchecked`). |
| [`tui.style`](style/tui.style.md) | Sets the style of a widget or pane directly, without a theme class. |
| [`tui.ansi`](style/tui.ansi.md) | Prints the ANSI escape prefix of a widget or pane style (no reset). A state without rules falls back to `normal`. |
| [`tui.class.ansi`](style/tui.class.ansi.md) | Prints the ANSI escape prefix of a theme class, without a widget. |
| [`tui.paint`](style/tui.paint.md) | Prints `TEXT` in the style of a widget or pane, followed by a reset. No newline. |
| [`tui.class.paint`](style/tui.class.paint.md) | Prints `TEXT` in the style of a theme class, followed by a reset. No newline. |
| [`tui.paint.reset`](style/tui.paint.reset.md) | Clears the rendering cache, forcing a full redraw on the next flush. |
| [`tui.style.sgr`](style/tui.style.sgr.md) | Resolves the style of a widget or pane into variables, without a subshell. |
| [`tui.class.style`](style/tui.class.style.md) | Resolves a theme class into variables, without a subshell. Sets `TUI_FG`, `TUI_BG`, `TUI_MODS`. |
| [`tui.class.sgr`](style/tui.class.sgr.md) | Resolves a theme class into an escape prefix, without a subshell. |
| [`tui.class.names`](style/tui.class.names.md) | Stores every class and pseudo-state key of the loaded theme, sorted, in the array `TUI_CLASSES`. Fork-free. |
| [`tui.glyph.get`](style/tui.glyph.get.md) | Resolves a themeable glyph into `TUI_GLYPH`, without a subshell: the variant's value, else the base type's, else the built-in default. |
| [`tui.glyph.set`](style/tui.glyph.set.md) | Sets a themeable glyph at run time, for apps that let the user pick a look. |
| [`tui.glyph.user`](style/tui.glyph.user.md) | Sets one part of the user's own design, `custom`, and keeps it across theme changes. The Settings page uses it; the choice is stored as `glyph.TYPE.KEY` in the app's `dabt.conf`. |
| [`tui.glyph.available`](style/tui.glyph.available.md) | Lists the glyphs the Settings page offers for a slot, without a subshell. Every slot of a group gets the same list, so a checked and an unchecked mark are picked from one set. |
| [`tui.variant.default`](style/tui.variant.default.md) | Sets the design widgets of one type use when they name no [`variant`](/api/widgets/tui.variant.html) of their own. The Settings page uses it; the choice is stored as `variant.TYPE` in the app's `dabt.conf`. |
| [`tui.variant.list`](style/tui.variant.list.md) | Lists the designs the loaded theme defines for one widget type, without a subshell. |
| [`tui.cache.theme_clear`](style/tui.cache.theme_clear.md) | Forgets every memoized stylesheet, so the next load parses the files again. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative style/tui.load_theme.md %}

{% include_relative style/tui.class.md %}

{% include_relative style/tui.style.md %}

{% include_relative style/tui.ansi.md %}

{% include_relative style/tui.class.ansi.md %}

{% include_relative style/tui.paint.md %}

{% include_relative style/tui.class.paint.md %}

{% include_relative style/tui.paint.reset.md %}

{% include_relative style/tui.style.sgr.md %}

{% include_relative style/tui.class.style.md %}

{% include_relative style/tui.class.sgr.md %}

{% include_relative style/tui.class.names.md %}

{% include_relative style/tui.glyph.get.md %}

{% include_relative style/tui.glyph.set.md %}

{% include_relative style/tui.glyph.user.md %}

{% include_relative style/tui.glyph.available.md %}

{% include_relative style/tui.variant.default.md %}

{% include_relative style/tui.variant.list.md %}

{% include_relative style/tui.cache.theme_clear.md %}

</div>

<!-- /api -->

## Border styles

<!-- api: tui.border.register -->

| Function | Summary |
|---|---|
| [`tui.border.register`](style/tui.border.register.md) | Adds a border style, usable as `border="NAME"` (and `divider="NAME"`) in markup. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative style/tui.border.register.md %}

</div>

<!-- api: tui.theme.set tui.theme.clear tui.theme.current tui.theme.reload tui.theme.list tui.theme.pick -->

| Function | Summary |
|---|---|
| [`tui.theme.set`](style/tui.theme.set.md) | Sets an app-wide stylesheet that is layered over every page's own theme, and reloads the current page. |
| [`tui.theme.clear`](style/tui.theme.clear.md) | Removes the app-wide stylesheet and reloads the current page. |
| [`tui.theme.current`](style/tui.theme.current.md) | Prints the path of the app-wide stylesheet (empty when none). |
| [`tui.theme.reload`](style/tui.theme.reload.md) | Reloads the current page, keeping focus and cursor when the focused widget still exists. |
| [`tui.theme.list`](style/tui.theme.list.md) | Prints every selectable theme overlay as `NAME<TAB>FILE`, one per line, sorted by name. |
| [`tui.theme.pick`](style/tui.theme.pick.md) | Applies the theme `NAME` from [`tui.theme.list`](/api/style/tui.theme.list.html) to every page and remembers it for the next start. Without `NAME` it removes the overlay (page default). |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative style/tui.theme.set.md %}

{% include_relative style/tui.theme.clear.md %}

{% include_relative style/tui.theme.current.md %}

{% include_relative style/tui.theme.reload.md %}

{% include_relative style/tui.theme.list.md %}

{% include_relative style/tui.theme.pick.md %}

</div>

<!-- /api -->
