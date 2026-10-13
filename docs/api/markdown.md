# Markdown

`lib/markdown/tui_markdown.sh` - Markdown renderer for reading and editing: wrapped, styled rows with a source-line map, plus a source-preserving styler for editors. ← [API index](README.md) for the full module list.

## Render and style

<!-- api: tui.md.render tui.md.style tui.md.strip tui.md.row_for_line tui.md.line_for_row tui.md.style_set tui.md.mono tui.md.breaks tui.md.fonts tui.md.heading_font tui.md.style_spec tui.md.style_spec_of tui.md.style_reset tui.md.heading_font_of tui.md.config_apply -->

| Function | Summary |
|---|---|
| [`tui.md.render`](markdown/tui.md.render.md) | Renders Markdown `TEXT` into rows of at most `WIDTH` cells. |
| [`tui.md.style`](markdown/tui.md.style.md) | Styles Markdown `TEXT` for source editors: one row per source line, with every character kept. |
| [`tui.md.strip`](markdown/tui.md.strip.md) | Removes the SGR (color and attribute) sequences from `STR`, then prints the result or stores it in `VAR`. |
| [`tui.md.row_for_line`](markdown/tui.md.row_for_line.md) | Stores in `VAR` the 0-based index of the first rendered row of the block that holds source line `LINE` (1-based). |
| [`tui.md.line_for_row`](markdown/tui.md.line_for_row.md) | Stores in `VAR` the source line (1-based) of rendered row `ROW`, using the last render. |
| [`tui.md.style_set`](markdown/tui.md.style_set.md) | Replaces the SGR sequence of one style class. |
| [`tui.md.mono`](markdown/tui.md.mono.md) | Switches the style table to attributes only (bold, underline, reverse, dim, no colors) with `on`, or back to the colored table with `off`. |
| [`tui.md.breaks`](markdown/tui.md.breaks.md) | Chooses whether a single newline inside a paragraph breaks the line (`on`) or joins the lines with a space (`off`, the default). |
| [`tui.md.fonts`](markdown/tui.md.fonts.md) | Switches headings that have a font (see [`tui.md.heading_font`](/api/markdown/tui.md.heading_font.html)) between block letters (`on`) and plain styled text (`off`, the default). |
| [`tui.md.heading_font`](markdown/tui.md.heading_font.md) | Sets the block font used for heading level `LEVEL` while [`tui.md.fonts`](/api/markdown/tui.md.fonts.html) is on. |
| [`tui.md.style_spec`](markdown/tui.md.style_spec.md) | Restyles one Markdown style class from `SPEC`, given as `FG[/BG][:MOD,MOD...]`. |
| [`tui.md.style_spec_of`](markdown/tui.md.style_spec_of.md) | Stores in `VAR` the spec of the current style of `CLASS`. |
| [`tui.md.style_reset`](markdown/tui.md.style_reset.md) | Restores the default style of `CLASS`, or of every style class when `CLASS` is omitted. |
| [`tui.md.heading_font_of`](markdown/tui.md.heading_font_of.md) | Stores in `VAR` the font name of heading level `LEVEL`, or `style` when that level has no font. |
| [`tui.md.config_apply`](markdown/tui.md.config_apply.md) | Loads the persisted Markdown settings from the app config: `md.fonts` (0/1), `md.breaks` (0/1), `md.link_url` (`inline` or `hidden`), `md.font.N` (a font name or `style`, `N` = 1..6) and `md.style.CLASS` (a style spec). |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative markdown/tui.md.render.md %}

{% include_relative markdown/tui.md.style.md %}

{% include_relative markdown/tui.md.strip.md %}

{% include_relative markdown/tui.md.row_for_line.md %}

{% include_relative markdown/tui.md.line_for_row.md %}

{% include_relative markdown/tui.md.style_set.md %}

{% include_relative markdown/tui.md.mono.md %}

{% include_relative markdown/tui.md.breaks.md %}

{% include_relative markdown/tui.md.fonts.md %}

{% include_relative markdown/tui.md.heading_font.md %}

{% include_relative markdown/tui.md.style_spec.md %}

{% include_relative markdown/tui.md.style_spec_of.md %}

{% include_relative markdown/tui.md.style_reset.md %}

{% include_relative markdown/tui.md.heading_font_of.md %}

{% include_relative markdown/tui.md.config_apply.md %}

</div>

<!-- /api -->

## Editor overlay and pages

<!-- api: tui.md.style_lines tui.md.fence_before tui.md.show tui.md.show_file tui.md.forget -->

| Function | Summary |
|---|---|
| [`tui.md.style_lines`](markdown/tui.md.style_lines.md) | Styles consecutive source lines for an editor overlay: one row per `LINE`, characters unchanged, delimiters in the marker class. |
| [`tui.md.fence_before`](markdown/tui.md.fence_before.md) | Stores in `VAR` the code-fence state (`""` or `CHAR:LEN`) in force at source line `TOP` (0-based) of `TEXT`. |
| [`tui.md.show`](markdown/tui.md.show.md) | Renders `TEXT` as Markdown into the scrolling pane `PANE` (`scroll="v"`). |
| [`tui.md.show_file`](markdown/tui.md.show_file.md) | Renders the contents of `FILE` into the scrolling pane `PANE`, as [`tui.md.show`](/api/markdown/tui.md.show.html) does. Returns `1` when `FILE` cannot be read. |
| [`tui.md.forget`](markdown/tui.md.forget.md) | Stops re-rendering a pane that was filled by [`tui.md.show`](/api/markdown/tui.md.show.html) or `<markdown>`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative markdown/tui.md.style_lines.md %}

{% include_relative markdown/tui.md.fence_before.md %}

{% include_relative markdown/tui.md.show.md %}

{% include_relative markdown/tui.md.show_file.md %}

{% include_relative markdown/tui.md.forget.md %}

</div>

<!-- /api -->

## Documents in panes

The settings that choose how Markdown is drawn (profile, tables, images, highlighting), and the navigation, search, folding and copy functions of a document shown in a pane.

<!-- api: tui.md.profile tui.md.tables tui.md.table_overflow tui.md.images tui.md.image_protocol tui.md.highlight tui.md.link_next tui.md.link_prev tui.md.link_open tui.md.on_link tui.md.on_navigate tui.md.back tui.md.search tui.md.search_next tui.md.search_prev tui.md.search_info tui.md.outline_choose tui.md.fold_toggle tui.md.copy tui.md.forward tui.md.search_prompt tui.md.keys tui.md.click tui.action.md_keys -->

| Function | Summary |
|---|---|
| [`tui.md.profile`](markdown/tui.md.profile.md) | Chooses the base look of the Markdown styles: DABT's own style table, or the active theme's `.md_CLASS` rules. |
| [`tui.md.tables`](markdown/tui.md.tables.md) | Chooses how pipe tables are drawn. |
| [`tui.md.table_overflow`](markdown/tui.md.table_overflow.md) | Chooses what happens to a table cell that is wider than its column. |
| [`tui.md.images`](markdown/tui.md.images.md) | Chooses what `![alt](src)` draws in a rendered document. |
| [`tui.md.image_protocol`](markdown/tui.md.image_protocol.md) | Stores in `VAR` the image protocol of the terminal: `kitty`, `iterm2` or `none`. |
| [`tui.md.highlight`](markdown/tui.md.highlight.md) | Registers the highlighter of a code fence language. |
| [`tui.md.link_next`](markdown/tui.md.link_next.md) | Focuses the next link of the document shown in `PANE`, wrapping at the end. |
| [`tui.md.link_prev`](markdown/tui.md.link_prev.md) | Focuses the previous link of the document shown in `PANE`, wrapping at the start. |
| [`tui.md.link_open`](markdown/tui.md.link_open.md) | Follows the focused link of the document shown in `PANE`. Returns `1` when no link is focused. |
| [`tui.md.on_link`](markdown/tui.md.on_link.md) | Sets the function that [`tui.md.link_open`](/api/markdown/tui.md.link_open.html) calls first, as `FN URL TEXT PANE`. |
| [`tui.md.on_navigate`](markdown/tui.md.on_navigate.md) | Sets the function called as `FN FILE PANE` after a relative `.md` link has loaded `FILE` into `PANE`. |
| [`tui.md.back`](markdown/tui.md.back.md) | Returns `PANE` to the document and scroll position before the last followed link or anchor. |
| [`tui.md.search`](markdown/tui.md.search.md) | Searches the rendered document in `PANE` for `TEXT`, case-insensitively as plain text. |
| [`tui.md.search_next`](markdown/tui.md.search_next.md) | Jumps to the next match of the search in `PANE`, wrapping at the end. |
| [`tui.md.search_prev`](markdown/tui.md.search_prev.md) | Jumps to the previous match of the search in `PANE`, wrapping at the start. |
| [`tui.md.search_info`](markdown/tui.md.search_info.md) | Stores in `VAR` the search state of `PANE`: `3/12`, `no match`, or an empty string when no search is set. |
| [`tui.md.outline_choose`](markdown/tui.md.outline_choose.md) | Opens a list ([`tui.choose`](/api/chrome/tui.choose.html)) of the headings of the document shown in `PANE`, indented by level; choosing one scrolls the pane to its top. |
| [`tui.md.fold_toggle`](markdown/tui.md.fold_toggle.md) | Folds or unfolds the section under a heading of the document shown in `PANE`. |
| [`tui.md.copy`](markdown/tui.md.copy.md) | Copies part of the document shown in `PANE` to the clipboard with [`tui.clipboard.copy`](/api/input/tui.clipboard.copy.html), and notifies. |
| [`tui.md.forward`](markdown/tui.md.forward.md) | Goes forward in `PANE`'s document history after [`tui.md.back`](tui.md.back.md): the document (and scroll position) the last back stepped over. Following a link starts a new trail and drops what was ahead. |
| [`tui.md.search_prompt`](markdown/tui.md.search_prompt.md) | Asks for a search text in a prompt, then runs [`tui.md.search`](tui.md.search.md) on `PANE` with it. An empty text clears the search; the match shown (`3/12`) or `No match` is announced as a notification. |
| [`tui.md.keys`](markdown/tui.md.keys.md) | Chooses which default Markdown keys act on `PANE` (`<markdown keys="..."/>` does the same in markup). |
| [`tui.md.click`](markdown/tui.md.click.md) | Follows the link drawn under the screen cell `X`,`Y` of `PANE`, exactly like focusing it and calling [`tui.md.link_open`](tui.md.link_open.md). A left click on a link in a Markdown pane does this by itself. |
| [`tui.action.md_keys`](markdown/tui.action.md_keys.md) | Opens a scrollable list of the Markdown reading commands (links, back, search, outline, folds, copy) with the keys bound to them right now: the defaults and the app's own binds. A command without a key shows `-`. Bound to `f2` by default, and listed in the command palette as "Help: Markdown reading keybinds". |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative markdown/tui.md.profile.md %}

{% include_relative markdown/tui.md.tables.md %}

{% include_relative markdown/tui.md.table_overflow.md %}

{% include_relative markdown/tui.md.images.md %}

{% include_relative markdown/tui.md.image_protocol.md %}

{% include_relative markdown/tui.md.highlight.md %}

{% include_relative markdown/tui.md.link_next.md %}

{% include_relative markdown/tui.md.link_prev.md %}

{% include_relative markdown/tui.md.link_open.md %}

{% include_relative markdown/tui.md.on_link.md %}

{% include_relative markdown/tui.md.on_navigate.md %}

{% include_relative markdown/tui.md.back.md %}

{% include_relative markdown/tui.md.search.md %}

{% include_relative markdown/tui.md.search_next.md %}

{% include_relative markdown/tui.md.search_prev.md %}

{% include_relative markdown/tui.md.search_info.md %}

{% include_relative markdown/tui.md.outline_choose.md %}

{% include_relative markdown/tui.md.fold_toggle.md %}

{% include_relative markdown/tui.md.copy.md %}

{% include_relative markdown/tui.md.forward.md %}

{% include_relative markdown/tui.md.search_prompt.md %}

{% include_relative markdown/tui.md.keys.md %}

{% include_relative markdown/tui.md.click.md %}

{% include_relative markdown/tui.action.md_keys.md %}

</div>

<!-- /api -->
