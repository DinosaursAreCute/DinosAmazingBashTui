# Declarative TUI markup

The project includes a lightweight HTML/XML-like config format for building TUIs
declaratively instead of hand-calling `tui.*` functions. The loader
(`lib/markup/tui_markup.sh`) is pure **bash + POSIX utilities only**.

It is sourced automatically by `tui.sh`, so `tui.load` and `tui.goto` are
available anywhere `tui.sh` is sourced.

## Editor autocompletion

[share/tui.xsd](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/share/tui.xsd) describes the tag/attribute set for
editors that support XSD-based XML autocompletion and validation (e.g. the
Red Hat XML extension in VS Code). It's purely an editing aid - the loader
doesn't read or enforce it. Reference it from a page's root tag:

```xml
<tui xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="tui.xsd">

```

## Example

```bash
source lib/tui.sh
tui.start "config/home.xml"

```

`tui.start` handles the full lifecycle - `tui.init`, `tui.load`, `tui.run`, and
guaranteed terminal cleanup on exit/error - so a config-driven TUI only needs
to define its markup file. Use `tui.init` + `tui.load` + `tui.run` directly
only if you need to run custom setup between those steps. Or run the bundled demo:

```bash
bin/markup_demo.sh

```

## Format rules

* One tag per line. Attributes are `name="value"` (double quotes only).
* Tags are either self-closing (`<pane .../>`) or open/close pairs (`<pane ...>` … `</pane>`).
* `<!-- comments -->` on their own line are ignored.

## Supported tags

* `<tui>` – root wrapper (ignored by the parser).
* `<script src="…"/>` – sources a bash file (callbacks) before its actions are used. Path resolves relative to the file it appears in.
* `<theme src="…"/>` – loads a CSS-like stylesheet. Path resolves relative to the file it appears in.
* `<include src="…"/>` – inlines another markup file at parse time. Useful for shared fragments like a nav bar.
* `<pane id="x" split="h|v|grid" weight="N" title="…" border="…" align="left|center|right|fill" valign="top|middle|bottom" min_width="N" min_height="N" max_width="N" max_height="N" scroll="none|v|h|both" strict_fit="true|false" class="…">` – layout node. `split="h"/"v"` makes it a container; children become the `tui.hsplit`/`tui.vsplit` list. `split="grid"` is documented separately below.
* `<label id="x" pane="p" row="N" text="…" align="…" valign="…" min_width="N" max_width="N" class="…"/>`
* `<input id="x" pane="p" row="N" label="…" placeholder="…" submit="fn" align="…" valign="…" min_width="N" max_width="N" label_align="left|center|right" label_width="N" class="…"/>`
* `<button id="x" pane="p" row="N" text="…" action="fn" align="…" valign="…" min_width="N" max_width="N" class="…"/>`
* `<button id="x" pane="p" row="N" text="…" page="other.xml"/>` – navigates to another page instead of calling a bash function.
* `<checkbox id="x" pane="p" row="N" label="…" checked="true|false" action="fn" align="…" valign="…" min_width="N" max_width="N" class="…"/>` – a boolean toggle widget (`[x] Label` / `[ ] Label`), focusable like a button. `action` is called with the new value ("0"/"1") after every toggle, whether triggered by a click or by Enter while focused. `tui.get`/`tui.set`/`tui.update` work on it exactly as on any other widget.
* `<tabs id="x" header_pane="p1" content_pane="p2"> <tab .../> … </tabs>` – documented separately below.

## Grid layout (`split="grid"`)

A third split mode alongside `h`/`v`, for "several elements side by side"
without hand-declaring one sub-pane per cell:

```xml
<pane id="toolbar" split="grid" rows="1" cols="4" fit="stretch">
  <pane id="cell_a" border="none"/>
  <pane id="cell_b" border="none"/>
  <pane id="cell_c" border="none"/>
  <pane id="cell_d" border="none"/>
</pane>
```

Each child `<pane>` becomes one grid cell (an ordinary pane - put one
widget in it exactly as you would in any other pane), placed either:

* **loosely** - no `grid_row`/`grid_col`: filled into the next open cell,
  in document order, row-major; or
* **explicitly** - `grid_row="R" grid_col="C"` on the child pins it to
  that exact cell.

The two can be mixed freely on one grid; explicit cells are reserved
first, then loose children fill whatever's left. If there are more loose
children than empty cells, extra rows are appended automatically (reusing
the last row's weight) rather than dropping content.

**Attributes** (all optional except `split="grid"` itself):

* `rows`, `cols` - grid shape. Either or both may be **omitted**, and are
  computed from however many children the grid ends up with: only `cols`
  given → `rows = ceil(N/cols)`; only `rows` given → `cols = ceil(N/rows)`;
  neither given → a roughly-square grid (`cols = ceil(sqrt(N))`).
* `fit="pack"` (default) - every row always has the full `cols` cells;
  an unfilled trailing cell renders as an ordinary empty pane.
* `fit="stretch"` - a row's empty cells are dropped instead, so its
  populated cells expand to fill the row evenly. This is what fixes "6
  items, 4 columns, the last 2 should be full-width, not narrow with two
  blanks next to them."
* `row_weights="1 2 1"`, `col_weights="1 1 1 1"` - space-separated weight
  lists (same weight semantics as `tui.hsplit`/`tui.vsplit`), one entry
  per row/column; missing entries default to `1`.

The imperative equivalent is `tui.grid PARENT ROWS COLS FIT ROW_WEIGHTS
COL_WEIGHTS NAME…`, which the markup parser itself is built on - see
`lib/tui.sh`.

## Tabs

Formalizes "a row of header buttons that swap a content pane" - the
pattern hand-rolled in earlier demo pages - into one declarative block:

```xml
<pane id="tabs_header" weight="1"/>
<pane id="content" weight="9" border="heavy"/>

<tabs id="mytabs" header_pane="tabs_header" content_pane="content">
  <tab id="tab_doc" text="Document" action="on_tab_doc"/>
  <tab id="tab_tbl" text="Table" action="on_tab_tbl" default="true"/>
</tabs>
```

`header_pane` and `content_pane` must already be declared panes (order in
the file doesn't matter, same as `pane="…"` on any widget). Each `<tab>`
becomes a header button, laid out as a 1-row grid across `header_pane`
(so `fit="stretch"`-style equal-width headers come for free). "Active"
reuses this framework's existing focus styling rather than a second style
state - the active tab's header button is simply the focused widget, so
any `.class:focus` rule already styles it. `default="true"` on one `<tab>`
picks the tab that starts active; if none is marked, the first one does.
`action` is exactly the callback you'd already write to populate
`content_pane` via `tui.output` - nothing about its body changes, `<tabs>`
only removes the button-wiring boilerplate around it. It's called with the
tab's own id as `$1`, so one shared `action` can serve many tabs (see
`config/docu_callbacks.sh`'s dynamic tabs below) - existing callbacks that
take no arguments are unaffected, bash just ignores the extra one.

**Two header styles**, set with `style="framed"` (default) or
`style="compact"` on `<tabs>` (imperative: `tui.tabs.compact TABS_ID
true` before `tui.tabs.build`):

* `framed` - each header is its own bordered cell (`.tab_header`
  class); needs at least 3 rows (top border, label, bottom border).
* `compact` - no border at all; the active tab is shown purely by a
  background-color change (`.tab_header_compact:focus` in `theme.css`)
  instead of a frame, so a 1-row header pane is enough. Use this wherever
  the header doesn't have 3 rows to spare.

## Dynamic tabs (built at runtime)

`<tabs>`/`<tab>` need every tab known at parse time. When the set isn't
known until runtime - e.g. one tab per file discovered in a directory -
build them from an `on_visit` callback with the same primitives `<tabs>`
itself is built on:

```bash
on_docu_visit() {
    local -a tab_ids=()
    local i file
    for i in "${!files[@]}"; do
        file="${files[$i]}"
        tui.tabs.add "doc_tab_$i" "$(basename "$file")" on_doc_tab_activate
        tab_ids+=("doc_tab_$i")
    done
    tui.tabs.build "doctabs" "tabs_header" "content" "${tab_ids[@]}"
}
```

See `config/docu_callbacks.sh` for the full version (it also derives a
short label from each file's own heading rather than its filename).

## Running a callback once a page is fully loaded (`on_visit`)

```xml
<tui on_visit="on_docu_visit">
```

Calls the named function once the page's panes and widgets are fully
built - on the page's initial load *and* every time `tui.goto` navigates
back to it. This is what makes dynamic tabs (above) possible: nothing in
the page's own markup needs to name the tabs, `on_visit` builds them from
whatever it finds at that moment.

## Dynamic layouts: the factory API

For layouts whose shape isn't known until runtime - "however many items
are in this list" - markup alone isn't enough, since XML has to name
every id up front. `tui.factory.*` (in `lib/tui.sh`) is the imperative
counterpart: it auto-generates unique ids under a namespace you choose,
and `tui.factory.clear NAMESPACE` tears every one of them back down
(widgets, and any panes from `tui.factory.grid`) in one call, so a
callback can rebuild a layout from scratch each time its data changes:

```bash
rebuild_item_list() {
    tui.factory.clear "items"                 # drop whatever was there
    tui.factory.grid "items" "list_pane" "${#my_items[@]}"   # size from count
    local i
    for i in "${!my_items[@]}"; do
        tui.factory.button "items" "${_TUI_FACTORY_GRID_CELLS[$i]}" 0 \
            "${my_items[$i]}" on_item_clicked
    done
    tui.render
}
```

* `tui.factory.label|button|input|checkbox NAMESPACE PANE ROW …` - same
  arguments as the plain `tui.label`/etc. constructors, minus the id (one
  is generated and left in `_TUI_FACTORY_LAST_ID` - read it right after
  the call if you need it: `tui.factory.button …; id="$_TUI_FACTORY_LAST_ID"`.
  These deliberately don't print the id: in a TUI, stdout is the screen,
  and a constructor called in a loop without wrapping it in `$(...)` would
  otherwise leak raw id text straight onto the terminal.
* `tui.factory.grid NAMESPACE PARENT COUNT [COLS] [FIT] [ROW_WEIGHTS] [COL_WEIGHTS]`
  - the dynamic-sizing counterpart to `<pane split="grid">`: takes an item
  **count** rather than a fixed shape, and leaves the resulting cell ids,
  in order, in `_TUI_FACTORY_GRID_CELLS` for you to populate.
* `tui.factory.clear NAMESPACE` - removes everything tagged under that
  namespace. Independent namespaces (different callbacks, different parts
  of a page) never collide with each other's ids.

This is deliberately not a templating engine - just id-management and
bulk teardown wrapped around the same constructors the markup parser
itself calls.

## Automatic content-fit checking

Besides the explicit `min_width`/`min_height` a pane can declare, its
actual content is also checked automatically on every full render (page
load and every terminal resize): the furthest widget row and longest
widget text placed in it, or - for a `tui.output`-fed pane - the line
count and max line width already tracked for scrolling. If the pane is
smaller than what its own content needs, the same `min space = …` warning
used for an explicit `min_width`/`min_height` violation appears, without
you having to declare one by hand. A pane with `scroll` enabled is exempt
(content taller/wider than the viewport is the normal, intended state for
one); set `strict_fit="false"` on a specific pane to opt it back out
entirely and rely on explicit `min_width`/`min_height` only.

## Performance tracking

Off by default. A page can opt in with `_TUI_PERF_TRACKING=1` (e.g. at the
top of its `<script>` file) to have every frame `tui.render` and friends
flush get timestamped; `tui.perf.mean_render_ms SECONDS` then returns the
mean render duration, in milliseconds, over the trailing window - useful
for watching your own layout's cost live instead of guessing. See
`config/debug.xml` / `config/debug_callbacks.sh` for a working example,
alongside a live tape of dispatched input events (set
`_TUI_ON_INPUT_EVENT` to a function to receive one) and hover/focus state.

## Scrolling Viewports

Panes can act as high-performance scrolling viewports by adding the `scroll` attribute.

* `scroll="v"`: Enables vertical scrolling.
* `scroll="h"`: Enables horizontal scrolling.
* `scroll="both"`: Enables multi-axis scrolling.

Content is injected into a scrollable pane using `tui.output "pane_id" "content"` in a callback script. Scrolling is processed via a high-performance AWK shader and utilizes the "Jump-to-Click" pattern for immediate responsiveness. Users can navigate via the mouse wheel, Shift+Mouse Wheel (horizontal), clicking directly on the generated scrollbar tracks, or using Vim bindings (`hjkl`) and Shift+Arrow keys.

## Alignment

`align` (horizontal) and `valign` (vertical) control how a widget's text is
positioned within its row.

* Per node (pane): `align`/`valign` on a `<pane>` set the default for every widget placed in it (`tui.pane_align`, `tui.pane_valign`).
* Per element: `align`/`valign` on a `<label>`/`<input>`/`<button>` override that default for just that widget (`tui.align`, `tui.valign`).
* Precedence: widget's own value > its pane's value > built-in default (center horizontally for buttons, left/top for everything else).
* `align="fill"` paints the entire row width with the element's fg/bg/mods instead of only the text.
* `valign` reinterprets a widget's row as an offset from the chosen anchor instead of an absolute line: `top` counts down, `bottom` counts up, and `middle` offsets from the vertical center.

### Aligning a widget's sub-components (input label vs. field)

Use `label_width` to reserve a fixed-width box for the label and `label_align`
to position the label text within that box; the field then fills the
remaining row width:

```xml
<input id="inp_name" pane="form" row="0" label="Name:" label_width="12" label_align="right"/>

```

## Minimum / maximum sizes

* `min_width`/`min_height` on a `<pane>`, and `min_width` on a widget, declare the smallest space something is allowed to render into. If the actual available space is smaller, a warning is shown in place of the normal content: `min space = WxH` for panes, `min space = N` for a widget's row.
* `max_width`/`max_height` cap how large it is allowed to grow - extra space is simply left blank.

## Styling

`lib/style/tui_style.sh` adds a CSS-like theme system, loaded with `<theme src="theme.css"/>`:

```css
.danger_button        { fg: white; bg: #b00020; mods: bold; }
.danger_button:focus  { fg: white; bg: #ff3333; mods: bold; }

```

`fg`/`bg` accept a `colors.sh` name (e.g. `red`) or a `#RRGGBB` hex value;
`mods` is a space-separated list of `style.*` modifiers (e.g. `bold underline`).
`:focus`/`:border`/`:title`/`:hover` are optional pseudo-state variants.

`:hover` applies to a *widget* (button/input) while the mouse pointer sits
over it; a class with no `:hover` rule leaves hovering that widget with no
visual effect. It has no effect on panes.

`:checked` / `:unchecked` style a *checkbox* by its value (on / off). They replace the normal look; `:focus` and `:hover` still win while the checkbox is focused or hovered, and any field the state leaves out falls back to the normal look. A checkbox with no such rules is drawn as before.

A pane's border instead reacts to `:focus`: it switches to the class's
`:focus` style (falling back to `:border`) while any widget inside that
pane currently has keyboard focus, and reverts the moment focus moves
elsewhere - recoloring just the border ring, never the interior or any
scrolled content.

Apply a class with `class="danger_button"`.

## Runtime text expressions

`text`/`label` attributes on `<label>`/`<button>` may embed
`${command args…}` - resolved by running that shell command and substituting its stdout, every time the widget is redrawn:

```xml
<label id="lbl_rule" pane="output" row="0" text="${terminal_renderer.sh divider 'Section'}"/>

```

Content isn't re-resolved automatically on a timer; call `tui.redraw` (an alias for `tui.render`) to force a full repaint on demand.

## Multi-page TUIs

Each markup file is a self-contained page (its own `<tui>…</tui>`). A button's `page` attribute (instead of `action`) wires up an internal handler that calls:

```bash
tui.goto "other.xml"

```

`tui.goto` clears all panes/widgets, resets to a full-screen root pane, loads
the target file, and re-renders.

## Callback sourcing

`<script>` files are sourced as plain bash - `tui.sh` is already loaded by the
time they run, so they can call `tui.get`, `tui.update`, `tui.exec`, `tui.stop`,
etc. directly.
