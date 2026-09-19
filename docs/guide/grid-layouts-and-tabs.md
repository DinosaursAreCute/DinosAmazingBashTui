# Developer Guide: Grid Layouts and Tabs

`bin/tui_markup.sh` and `bin/tui.sh` provide two features for arranging
several elements together without hand-declaring one sub-pane per element:
`split="grid"` and `<tabs>`. This guide covers when to reach for each, how
placement and sizing actually resolve, and the gotchas that aren't obvious
from the tag reference in `docs/guide/markup.md`.

## 1. Grid layouts

### The problem it solves

Before `split="grid"` existed, a row of N buttons meant declaring N
separate sub-panes by hand, each with `weight="1"` and `border="none"`,
one widget per pane - see `config/components.xml`'s toolbar for what that
looks like at scale. `split="grid"` is sugar over exactly that same
underlying mechanism (`tui.hsplit`/`tui.vsplit`), it just generates the
sub-panes for you from a higher-level description.

### Basic usage

```xml
<pane id="toolbar" split="grid" rows="1" cols="4">
  <pane id="cell_a" border="none"/>
  <pane id="cell_b" border="none"/>
  <pane id="cell_c" border="none"/>
  <pane id="cell_d" border="none"/>
</pane>
```

Each child `<pane>` becomes one grid cell - an ordinary pane. Put one
widget in it exactly as you would in any other pane
(`<button pane="cell_a" row="0" .../>`).

### Placement: loose, explicit, or mixed

A child with no `grid_row`/`grid_col` is **loose** - it fills the next
open cell, in document order, row-major (row 0 left-to-right, then row 1,
and so on). A child with both attributes set is **explicit** - it claims
that exact cell. The two can be mixed freely on one grid:

```xml
<pane id="toolbar" split="grid" cols="3" border="none">
  <pane id="cell_a" border="none"/>                           <!-- loose -->
  <pane id="cell_b" grid_row="0" grid_col="2" border="none"/>  <!-- explicit -->
  <pane id="cell_c" border="none"/>                           <!-- loose -->
  <pane id="cell_d" border="none"/>                           <!-- loose -->
</pane>
```

Explicit cells are reserved first; loose children then fill whatever's
left, in the order they appear - `cell_b`'s explicit claim on `(0,2)`
doesn't change where `cell_a`/`cell_c`/`cell_d` land, it just takes that
one cell out of the pool before they're placed. If loose children
outnumber the empty cells left over, the grid grows extra rows rather
than dropping content - this is what makes a grid usable from the
factory API (§3) when the item count isn't known ahead of time.

A collision (two children both claiming the same explicit cell) keeps the
later one in the document and prints a warning to stderr - it won't halt
the page.

### Sizing: `rows`/`cols` are optional

Either or both may be omitted, and are computed from however many
children the grid actually ends up with (call that `N`):

| Given | Computed |
|---|---|
| `cols` only | `rows = ceil(N / cols)` |
| `rows` only | `cols = ceil(N / rows)` |
| neither | a roughly-square grid: `cols = ceil(sqrt(N))`, `rows = ceil(N / cols)` |

This is what lets a grid's shape track its content instead of being
pinned to a number you chose at authoring time - most useful when the
content itself is runtime-determined (§3).

### `fit`: what happens to a short row

With 6 items in a 4-column grid, the second row only has 2. `fit`
controls what happens to the other 2 cells in that row:

* **`fit="pack"`** (default) - they render as ordinary empty panes. A
  literal, fixed grid - every row is always `cols` cells wide, whether
  populated or not.
* **`fit="stretch"`** - they're dropped, and the row's 2 real cells
  expand to fill the full row width evenly instead of sitting narrow next
  to two blanks. This is the fix for "I have 6 elements, 4 fit a row, and
  I want the leftover 2 to be equal width, not narrow-with-gaps."

Pick `stretch` for anything that should look intentionally laid out
regardless of item count (a toolbar, a tab header); pick `pack` when a
visibly empty cell is meaningful (a fixed-shape board, a calendar grid).

### Weights

`row_weights="1 2 1"` / `col_weights="1 1 1 1"` are space-separated lists,
one entry per row/column, same weight semantics as `tui.hsplit`/
`tui.vsplit`'s `name:weight` pairs. A missing entry defaults to `1`.

### What a grid is *not*

`split="grid"` arranges **panes**, not widgets directly inside one pane.
Putting multiple buttons at arbitrary (row, col) coordinates inside a
*single* pane isn't supported - a pane's widgets are still positioned by
`row` alone, same as everywhere else in this framework. If you want
several widgets side by side, each one gets its own grid cell (a pane),
exactly like the toolbar example above. This is a deliberate scope limit:
extending widget positioning to a second (column) dimension would touch
hit-testing and the hover/focus redraw path, which is tuned to be cheap
specifically because it's a 1D (row-only) model - see
`docs/design/pointer-tracking-and-hover.md` for why that path is the way
it is.

### Imperative form

```bash
tui.grid PARENT ROWS COLS FIT ROW_WEIGHTS COL_WEIGHTS NAME…
```

Pure geometry - no placement logic. `ROWS`/`COLS` may be `""` for the
same auto-sizing rules above; `NAME…` is a flat, row-major list of cell
names (empty string = blank cell). The markup parser resolves explicit
vs. loose placement into exactly this flat list before calling it, so if
you're ever building a grid from bash directly, you're responsible for
that same resolution - or just supply names in the order you want them to
appear, which is the loose-only case and needs no resolution at all.

## 2. Tabs

### The problem it solves

"A row of header buttons that swap a content pane" used to mean manually
wiring: one button per tab (each in its own sub-pane, per the grid
section above), a callback per button that calls `tui.output` on the
shared content pane, and no persistent indication of which tab was last
selected. `config/case_study.xml` and `config/docu.xml` both hand-rolled
this identically before `<tabs>` existed.

### Declarative usage

```xml
<pane id="tabs_header" weight="1"/>
<pane id="content" weight="9" border="heavy"/>

<tabs id="mytabs" header_pane="tabs_header" content_pane="content">
  <tab id="tab_doc" text="Document" action="on_tab_doc"/>
  <tab id="tab_tbl" text="Table" action="on_tab_tbl" default="true"/>
</tabs>
```

`header_pane`/`content_pane` must already exist as panes somewhere in the
page (order doesn't matter, same as `pane="…"` on any widget). Each
`<tab>` becomes a header button, laid out as a 1-row grid across
`header_pane` - so the equal-width-headers behavior is exactly
`fit="stretch"` under the hood, for free.

`action` is the same callback shape you'd write for a plain button that
populates `content_pane` via `tui.output` - nothing about its body
changes. `<tabs>` only removes the wiring around it, and adds one thing:
it's called with the tab's own id as `$1`, so **one** `action` can serve
**many** tabs (see §2.3). A callback that ignores arguments is unaffected.

`default="true"` on one `<tab>` picks the tab that starts active; if none
is marked, the first one does.

### Active state has no second mechanism

A tab becoming "active" is implemented as: `tui.focus` is called on its
header button. That's it - there's no separate "is this tab active" style
state. Whatever `.class:focus` rule the header's theme class defines is
what shows the active tab, the same mechanism (and the same border-vs-hover
distinction) already covering every other focusable widget in this
framework. Concretely this means:

* You style the active tab by defining `:focus` on its class
  (`.tab_header:focus` / `.tab_header_compact:focus` in `theme.css`), not
  by inventing a new pseudo-state.
* Tabbing away from the header with the keyboard will visually "lose" the
  active-tab indication until focus returns to it - this mirrors how
  focus behaves everywhere else in the framework, and is a deliberate
  reuse rather than a half-finished feature.

### Two header styles: `framed` vs `compact`

```xml
<tabs id="mytabs" header_pane="tabs_header" content_pane="content" style="compact">
```

* **`framed`** (default) - each header is its own bordered cell
  (`.tab_header` class). Needs at least **3 rows**: top border, label,
  bottom border.
* **`compact`** - no border at all; the active tab is shown purely by a
  background-color change (`.tab_header_compact:focus`) instead of a
  frame. Needs only **1 row**.

**Use compact whenever the header pane is a thin strip** - a
`weight="4"`-style sliver of a taller layout is usually 1-2 rows at
ordinary terminal sizes, nowhere near the 3 a framed header needs.
`config/docu.xml` and `config/case_study.xml` both use compact for
exactly this reason; `config/tabs_demo.xml` demonstrates framed with a
header pane sized generously enough to actually fit it. If you're not
sure which your layout needs, compact is the safer default - it works at
any header height framed does, but not vice versa.

Imperative equivalent: `tui.tabs.compact TABS_ID true`, called before
`tui.tabs.build`.

### Tab labels are allowed to clip

Every header cell `tui.tabs.build` creates is exempted from the
content-fit checker (`strict_fit="false"`, see `docs/guide/markup.md`). A tab
label running out of room and clipping is ordinary, expected UI behavior
- the same as a nav sidebar button - not a "this pane is too small"
condition worth a warning. If you want that warning back for a specific
tab's header cell (e.g. you're deliberately testing layout limits), call
`tui.pane_strict_fit "header_pane_id_tabid_cell" true` after `tui.tabs.build`.

### 2.3 Dynamic tabs: building the set at runtime

`<tabs>`/`<tab>` need every tab known when the page is parsed. When the
set isn't known until runtime - one tab per file discovered in a
directory, one tab per item in a list fetched some other way - build them
imperatively instead, using the exact same two calls `<tabs>` itself
compiles down to:

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

`tui.tabs.add TAB_ID TEXT ACTION [DEFAULT]` registers one tab's data
without building anything yet (`tui.tabs.build` needs the full set at
once, since it lays the header out as a single grid). The shared `action`
receiving the tab id as `$1` (§2.1) is what makes "one handler, N
dynamically-created tabs" work - see `config/docu_callbacks.sh` for the
complete version, including deriving a short label from each file's own
heading instead of its filename.

This only runs at all if something calls it. `<tui on_visit="fn">`
(`docs/guide/markup.md`) is that something: it fires once a page's static
markup has been fully built, on every load including a `tui.goto`
revisit, which is exactly the moment "figure out what tabs exist" needs
to happen.

## 3. Putting it together: dynamic grids via the factory API

Grids and tabs both assume you already have a fixed-at-that-moment list
of things to place. When even *that* isn't known ahead of time - "however
many buttons this list of runtime data needs" - `tui.factory.*`
(`docs/guide/markup.md`) is the piece underneath both of them: auto-id
generation plus bulk teardown, so a callback can throw away an entire
dynamic layout and rebuild it from scratch when its data changes:

```bash
rebuild_item_grid() {
    tui.factory.clear "items"
    tui.factory.grid "items" "grid_pane" "${#my_items[@]}"
    local i
    for i in "${!my_items[@]}"; do
        tui.factory.button "items" "${_TUI_FACTORY_GRID_CELLS[$i]}" 0 \
            "${my_items[$i]}" on_item_clicked
    done
    tui.render
}
```

`tui.factory.grid` is `tui.grid`'s dynamic-sizing counterpart: it takes an
item **count** instead of a fixed shape (same optional-`cols` auto-sizing
rules as `split="grid"`), generates that many namespace-tracked ids, and
leaves them in `_TUI_FACTORY_GRID_CELLS` in order. `tui.factory.clear`
removes every widget *and* pane a namespace ever created, resetting any
grid parent back to a plain leaf pane - so calling `rebuild_item_grid`
again with a different-length `my_items` produces a correctly
differently-shaped grid, not a layout with the old cells still attached.
`config/debug.xml`'s "Rebuild grid" button is a live example - each click
picks a new random item count and rebuilds from zero.

**One thing to watch for:** `tui.factory.*` constructors deliberately
don't print the id they generate - read it from `_TUI_FACTORY_LAST_ID`
right after the call if you need it inline, rather than
`id="$(tui.factory.button …)"`. In a TUI, stdout is the screen; capturing
it is fine, but a call inside a loop that *isn't* wrapped in `$(...)`
would otherwise write raw id text straight onto the terminal, outside any
pane's clipping. This bit an early version of `config/debug_callbacks.sh`
itself - see the `CHANGELOG.md` entry if you want the full story.
