# Grid layouts and tabs

Two ways to arrange several things together without writing one sub-pane per thing by hand: `split="grid"` for cells in rows and columns, and `<tabs>` for a row of header buttons that swap a content pane. This guide covers when to use each, how placement and sizing resolve, and the details that are not obvious from the tag reference in [Pages: the markup format](markup.md).

## 1. Grid layouts

A row of four buttons is four panes side by side. `split="grid"` generates the panes from a description instead of you listing each one.

```xml
<pane id="toolbar" split="grid" rows="1" cols="4" border="none">
  <pane id="cell_a" border="none"><button id="btn_new"  text="New"  action="on_new"/></pane>
  <pane id="cell_b" border="none"><button id="btn_open" text="Open" action="on_open"/></pane>
  <pane id="cell_c" border="none"><button id="btn_save" text="Save" action="on_save"/></pane>
  <pane id="cell_d" border="none"><button id="btn_quit" text="Quit" action="tui.action.quit"/></pane>
</pane>
```

Each child `<pane>` becomes one grid cell - an ordinary pane. Put the widget inside it like in any other pane.

### Placement: loose, explicit, or mixed

A child with no `grid_row`/`grid_col` is **loose**: it fills the next open cell in document order, row by row. A child with both attributes **claims** that exact cell. The two can be mixed on one grid:

```xml
<pane id="toolbar" split="grid" cols="3" border="none">
  <pane id="cell_a" border="none"/>                           <!-- loose -->
  <pane id="cell_b" grid_row="0" grid_col="2" border="none"/>  <!-- explicit -->
  <pane id="cell_c" border="none"/>                           <!-- loose -->
  <pane id="cell_d" border="none"/>                           <!-- loose -->
</pane>
```

Explicit cells are reserved first; loose children then fill what is left in the order they appear. If loose children outnumber the free cells, the grid grows extra rows rather than dropping content. Two children claiming the same cell keep the later one and print a warning.

### Sizing: `rows` and `cols` are optional

Either or both may be left out and are computed from the number of children `N`:

| Given | Computed |
|---|---|
| `cols` only | `rows = ceil(N / cols)` |
| `rows` only | `cols = ceil(N / rows)` |
| neither | roughly square: `cols = ceil(sqrt(N))`, `rows = ceil(N / cols)` |

### `fit`: what happens to a short row

With 6 items in 4 columns the second row has 2. `fit` decides what happens to the other 2 cells:

- **`fit="pack"`** (default): they stay as empty cells. Every row is `cols` wide, whether filled or not. Use it where an empty cell means something (a board, a calendar).
- **`fit="stretch"`**: they are dropped and the row's real cells share the full width. Use it for anything that should look deliberate whatever the item count (a toolbar, a tab header).

### Weights

`row_weights="1 2 1"` and `col_weights="1 1 1 1"` are space-separated lists, one entry per row or column, with the same meaning as `weight` in a split. A missing entry is `1`. (Size tokens such as `30%` or `fill` work on the panes of a split; a grid is weights only.)

### What a grid is not

A grid arranges **panes**, not widgets inside one pane. Widgets in a pane are stacked, one per line. For several widgets side by side, give each its own cell, as in the toolbar above.

### `fixed`: identical cells that never stretch

`split="fixed"` is for rows of identical, aligned elements - a keyboard, a wall of tiles. Every child is exactly `size_w` x `size_h` characters, flowed left to right and wrapped when the row is full. Unlike `h`, `v` and `grid`, nothing stretches when the window changes; children that no longer fit are not drawn.

```xml
<pane id="keys" split="fixed" size_w="6" size_h="3">
  <pane id="k_q" border="single"><label id="lbl_q" text="Q" align="center"/></pane>
  <pane id="k_w" border="single"><label id="lbl_w" text="W" align="center"/></pane>
  <pane id="k_space" border="single" span="4"/>   <!-- four cells wide -->
  <pane id="k_enter" border="single" newline="true"/> <!-- starts a new row -->
</pane>
```

`size_w` and `size_h` default to 4 and 3. `span` makes a child that many cells wide, `newline` starts a new row. Cells have no border unless you give them one.

### The call form

```bash
tui.grid PARENT ROWS COLS FIT ROW_WEIGHTS COL_WEIGHTS NAME…
```

Pure geometry: `ROWS`/`COLS` may be `""` for the sizing rules above, and `NAME…` is a flat, row-major list of cell names (an empty string is a blank cell). The page loader resolves loose and explicit placement into exactly this list first.

## 2. Tabs

```xml
<pane id="tabs_header" height="3" border="none"/>
<pane id="content" border="heavy"/>

<tabs id="mytabs" header_pane="tabs_header" content_pane="content">
  <tab id="tab_doc" text="Document" action="on_tab_doc"/>
  <tab id="tab_tbl" text="Table" action="on_tab_tbl" default="true"/>
</tabs>
```

`header_pane` and `content_pane` are panes of the page (their order in the file does not matter). Each `<tab>` becomes a header button, laid out as a one-row grid across `header_pane` with equal widths (`fit="stretch"` under the hood). `action` is called with the tab's own id as `$1`, so **one** function can serve **many** tabs; a callback that ignores arguments is unaffected. Fill `content_pane` from it with `tui.output`. `default="true"` picks the tab that starts active; without one, the first starts.

### Which tab is active

The active tab is the focused header button: `tui.focus` is called on it, and the look comes from the `:focus` rule of its class (`.tab_header:focus`, `.tab_header_compact:focus`). There is no separate "active" state. If keyboard focus moves away from the header, the active-tab look goes with it, as for any focusable widget.

### Two header styles

```xml
<tabs id="mytabs" header_pane="tabs_header" content_pane="content" style="compact">
```

- **`framed`** (default): every header is a bordered cell (`.tab_header`) and needs a header pane at least **3 lines** high.
- **`compact`**: no border; the active tab shows as a background colour (`.tab_header_compact:focus`). A **1-line** header pane is enough.

Use `compact` whenever the header is a thin strip. It works at any height `framed` does, not the other way round. From code: `tui.tabs.compact TABS_ID true` before `tui.tabs.build`.

### Labels may clip

Header cells are exempt from the content-fit warning (`strict_fit="false"`): a label running out of room and clipping is normal, as in a menu. To get the warning back for one header, call `tui.pane_strict_fit "HEADER_PANE_TABID_cell" true` after `tui.tabs.build`.

### Dynamic tabs

`<tab>` tags need every tab known when the page loads. For a set known only at run time (one tab per file in a folder), build the tabs in `on_visit` with the two calls `<tabs>` itself compiles to:

```bash
on_docu_visit() {
    local -a tab_ids=()
    local i file
    for i in "${!files[@]}"; do
        file="${files[$i]}"
        tui.tabs.add "doc_tab_$i" "${file##*/}" on_doc_tab_activate
        tab_ids+=("doc_tab_$i")
    done
    tui.tabs.build "doctabs" "tabs_header" "content" "${tab_ids[@]}"
}
```

`tui.tabs.add TAB_ID TEXT ACTION [DEFAULT]` records one tab; `tui.tabs.build` needs all of them at once because it lays the header out as one grid. The shared action receives the tab id as `$1`. `share/demo/docu_callbacks.sh` is the complete version.

A page that contains `<tabs>` cannot be refreshed in place: [`tui.page.refresh`](../api/core/tui.page.refresh.md) rebuilds such a page in the background instead of changing a pane. Keep the tabs out of the panes an addon changes.

## 3. A grid whose size is known only at run time

When even the number of cells depends on data, `tui.factory.*` creates widgets under a namespace and removes them again in one call:

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

`tui.factory.grid` is `tui.grid` for a *count*: it generates that many tracked ids, applies the same optional-`cols` sizing and leaves the cell ids in order in `_TUI_FACTORY_GRID_CELLS`. `tui.factory.clear` removes every widget and pane the namespace created and turns a grid parent back into a plain leaf pane, so a shorter list really gives a smaller grid. The *Debug* page's "Rebuild grid" button is a live example.

Two things to know:

- The factory constructors do not print their id (stdout is the screen): read it from `_TUI_FACTORY_LAST_ID` right after the call.
- If the dynamic part can be written as markup with a `<for>` (a count and a template), prefer that and [`tui.page.refresh`](../api/core/tui.page.refresh.md): the structure stays in the page file and only the changed pane is rebuilt.
