# Markup v2 Roadmap

Plan for the next markup/render generation. Status: stages 0 and 1 done (tokenizer, tag-registry build, snapshot cache, parallel warm-up); see the status index in [markup-v2-implementation-plan.md](markup-v2-implementation-plan.md#status-index) for the rest.

## Constraints

- **Bash 5 + POSIX utils only.** No new deps, no compiled helpers, no ncurses.
- **Least code wins.** Every feature reduces to an existing or shared primitive (the way `split="grid"` is just nested h/v splits). Each phase deletes the code it supersedes; net LOC should fall or stay flat.
- **Fork-free hot paths.** No `$( )`, pipes or external commands in input → layout → paint → flush. Results are returned through globals (`_R`, `_WSR`…) and `printf -v`.
- **TDD.** Write the test first. Unit suite: **< 200 ms per 100 tests**.
- **Back-compat.** Existing pages load unchanged; `pane="…"`/`row="…"` and `weight` stay as legacy forms.

## Mental model

```
markup ──parse──▶ node store ──expand/patch──▶ node store ──build──▶ engine state
                  (DOM)        include/template/            (panes, widgets)
                               component/addon/for/if             │
                                                           layout (measure ↓ arrange ↑)
                                                                  │
          terminal ◀──flush── frame rows ◀──paint── display list ◀┘ (dirty nodes only)
```

1. **Everything is a node.** Panes, widgets and layers are all nodes, and every node has a registered type.
2. **One layout primitive:** a pane that splits its children along an axis. Everything else desugars into it.
3. **One mutation API.** Parse-time expansion, addons and runtime changes all use the same node ops.
4. **Callbacks mutate, the frame renders.** API calls mark nodes dirty, and the loop flushes once per iteration.

## Features

Grouped by primitive. Items marked ⊂ are sugar for the primitive in their section header.

### A. Nodes and parsing
- Real tokenizer: multi-line tags, `'`/`"` quotes, entities, text content (`<button>Save</button>`).
- Widgets nest inside panes, and panes can mix widgets and child panes. `pane="…"` and `row="…"` are optional.
- Anonymous nodes get auto ids.
- ⊂ `<row>`, `<col>`, `<spacer/>`, `<divider/>`, `<group>`.

### B. Sizing (one constraint model for panes *and* widgets)
- Units: `20` (cells), `30%`, `2fr`, `auto`, `fill`, `clamp(a,b,c)`.
- `width`/`height`/`size` plus `min_*`/`max_*` on every node. A fixed size beats min and max; the validator warns when they conflict.
- `expand="x|y|both"` grows the widget (paint and hitbox) to fill its cell.
- `hitbox="text|row|cell|pane"` and `hit_pad="v h"` grow only the hit area. Siblings may not overlap (validator warning), and on overlap the topmost node wins.
- `padding`, `margin`, `gap` and `shrink="false"`.

### C. Layout (all desugar to splits)
- ⊂ `grid`: already nested splits. Adds `row_span`/`col_span`, named `areas` and `auto_fill`.
- ⊂ `flex`: a split with size units, `justify`, `align` and `order`. `wrap` generates row splits at layout time, the same way grid does.
- ⊂ `flow`: `flex` with `wrap` on and `auto` sizes.
- ⊂ `dock`: rewritten into nested splits at expand time.
- `stack`/`absolute`: children become layers (see F).
- Responsive: `hide_below`, `split_below="80:v"`, `<when cols="<80">` and `attr.sm`/`attr.lg` per breakpoint.
- `overflow="scroll|clip|ellipsis|hide"` and `priority` decide what gets dropped when space runs out.
- `tui.layout.register NAME` for custom engines, which must emit splits or layers.

### D. Frames (line canvas)
- ⊂ `fuse="true"`: children are drawn borderless, and the parent draws its frame plus the dividers on a line canvas. Junctions (`┬┼├┤┴`, and mixed single/double/heavy) resolve through one lookup table. Nested fused panes merge automatically.
- `divider="single|double|none"`, `divider_class`, `title_pos="top|divider|bottom"`, `title_align`.
- Border styles: `rounded`, `dashed`, `ascii` and per-side borders. They are just more line-canvas glyph sets.

### E. Interaction zones (one hit index)
- Scrollbars: hitbox **3 columns wide** (the bar ±1, clamped to the pane's own rect). The drawn bar stays 1 column and padding doesn't change. The horizontal bar gets 3 rows.
- ⊂ `resizable="x|y|both"`, `handle="corner|edge|divider"`: dragging a fused divider resizes both neighbours; dragging a corner resizes a layer. Min/max are respected, double-click resets, and there's a keyboard resize mode. `on_resize` fires on change.
- ⊂ Collapse: `collapsible`, `collapsed` and `collapse_to="title|0"` on panes and widgets. It's implemented as a size override, with a chevron zone to toggle it. Sugar built on it: `<details>`, `<accordion>`, `tui.collapse ID [true|false|toggle]` and `on_toggle`.
- Widget hitboxes, hit padding and title bars (drag to move) live in the same index.

### F. Layers (floating and detachable panes)
- A **layer** is a pane outside the split tree. It has `z`, `x`/`y`/`width`/`height` and `anchor="screen|parent|#id"`, and is clamped to the screen on resize.
- Floating panes: `float="true"` on a pane, with `movable`, `resizable`, `closable` and `minimizable`. Focusing or clicking one raises it. Edges snap, and a keyboard move/resize mode exists.
- **Detachable panes:** `detachable="true"`.
  - Drag the title bar out, or run a command, to detach. The node moves from its split into a new layer; siblings reflow, or a placeholder is left with `leave="placeholder|collapse"`. The subtree keeps its widgets, focus, scroll position and values.
  - While dragging, dock targets (left/right/top/bottom/tab) are drawn as a layer; dropping inserts the node into that split.
  - `dock_group` limits which containers accept the node. Events: `on_detach`/`on_dock`. `persist="layout"` stores the arrangement.
- ⊂ Every overlay is a layer with flags:
  - `<window>`, `<modal>` (focus trap, Esc), `<dialog>`
  - `<popup anchor>`, `<tooltip for>`, `<contextmenu for>`, `<toast>`
  - maximize/zoom: a layer that covers its parent

  This replaces the special-cased `lib/chrome/tui_modal.sh` overlay registry.

### G. Scrolling
- Any pane with `scroll` can scroll widgets as well as `tui.output`. Content height comes from the arranged children, and nodes outside the viewport aren't painted (virtualization).
- `scroll_into_view` when focus moves, `tui.scroll.to ID`, `sticky="top"` rows, and wheel events go to the innermost pane that can still scroll.

### H. Focus
- `focusable` and `tabbable` flags with defaults per type (interactive widgets: both; labels, progress and plain panes: neither; scroll panes and collapsibles: focusable only).
- `tab_order="N"`: `0` = first, `-1` = last, unset = document order. For N > 0, every value 1..N-1 should exist; gaps and duplicates are warnings, not errors. Ties are ordered by document position.
- `focus_group` + `focus_nav="arrows|tab|both"`, `focus_wrap`, `autofocus`, `focus_next`/`focus_prev`, `on_focus`/`on_blur`. Layers can form focus scopes (trap, then restore).
- `tabbable` without `focusable` is a validator error.

### I. Page state (one store: `page|id|field`)
- `keep_focus="true"`: the same id on the next page keeps focus. `<tui focus_on_enter="id|keep|first">` sets the page default.
- `keep_value="true"` and `<tui keep_state="true">` save value, cursor, scroll, selection and collapsed state.  `persist="disk"` also writes them to `$TUI_HOME/state/store`; `keep_focus` and `<tui focus_on_enter>` keep the focus.
- `persist="session|disk"`: disk storage is a `declare -p` dump under `TUI_HOME`.
- Reset: `tui.page.reset [PAGE]`, `tui.page.reset_field ID` and `tui.page.reset_all`. Each is also an action and a palette command.
- ⊂ Shells: `<tui shell="shell.xml">` + `<outlet/>`. The shell nodes are never torn down, so they keep focus and state for free.

### J. Node ops (one mutation API)
Ops: `clone`, `insert (append|prepend|before|after)`, `replace`, `remove`, `set attr`, `wrap`, `move`. Each feature below is built from them:
- ⊂ `<include>` with params, `<template>` + `<use>`, `<slot>`/`<fill>`, `<component name src>`, parse-time `<for>`/`<if>`.
- ⊂ **Addon XML:** `<addon target="page.xml|*" id priority>` holding op tags, with `ref=` selectors. Addons are discovered in `TUI_HOME/apps/<app>/addons/` and plugins. Their ids are prefixed with the addon id unless it opts out. `tui.addon.load`/`unload` rebuild only the affected subtree.
- ⊂ Detach/dock (F) = `move`.
- ⊂ Factories (`tui.factory.*`) = `insert` into a namespace + `remove` by namespace.

### K. Attribute cascade (one resolver)
Precedence, lowest first: `<defaults tag=…>` → CSS layers → `class` → `style=""` → reactive value → explicit markup attribute → runtime `tui.set`.
- CSS: selectors `#id`, `tag`, `.a.b`, `>`; pseudo-states `:disabled`, `:active`, `:selected`, `:collapsed`; `var(--x)`; layout props (`border`, `padding`, `gap`, `size`…).
- **Addon CSS:** `@layer app, theme, addon;`, `@extend`, per-property patches, and `tui.theme.add`/`remove` at runtime.
- Reactive attributes: `{{a ?? 'x'}}` (`??` falls back when the value is unset, empty or `false`), `a ? b : c`, `! && || == !=` and `arr[key]`. Expressions compile once to a bash snippet at parse time. A dependency graph maps each var to the nodes using it, and `tui.state.set` marks them dirty.
- `bind="var"` for two-way binding. `disabled`, `hidden`, `readonly` and `data-*` work on every node.

### L. Scripts and validation
- Several `<script src>` tags per page, globs, and optional `ns="prefix"`.
- Collision check: diff `declare -F` and globals before and after each script. Reported:
  - functions defined twice (and which one wins)
  - redefined `tui.*` functions
  - writes to `_TUI_*`
  - functions outside the declared `ns`
  - globals shared between scripts without being declared shared
- Semantic rules, added to the existing `tui.validate.*` registry:
  - dangling `action=`, `on_*=`, `page=` or `ref=` targets
  - duplicate ids after expansion
  - include cycles
  - `tab_order` gaps and duplicates
  - overlapping hitboxes
  - fixed sizes that don't fit
  - classes used but never defined
  - duplicate key bindings
  - `keep_focus` ids missing on the target page
  - undefined variables in expressions
- **CSS validation:** syntax and value errors; warnings for missing interactive states (`:hover`/`:focus`/`:active`/`:checked`) on classes used by elements that support them, pseudo-states that can never apply, framework and common classes missing for the widgets on a page, incomplete themes, undefined classes and invisible text (`fg` = `bg`). Driven by per-widget style contracts in the registry.
- `dabt lint`, strict mode, XSD generated from the tag/attr registries, hot reload (`dabt dev`), an inspector layer (ids, rects, hitboxes, tab order) and `dabt fmt`.

### M. Widgets and extension points
- Widgets: `tree`, `menu`, `radio`, `slider`, `number`, `date`, `log` (wraps `tui.exec`), `markdown`, `chart` (built on `terminal_renderer.sh`), `statusbar`, `breadcrumb`, `badge`. Data sources: `items_from="fn"`, `src="x.csv"`, `<column>`.
- Registries, all using one shape (`tui.register KIND NAME fn…`): tags, widget types (`measure paint key mouse`), layout engines, validators, pseudo-states, expression functions, node-op hooks (`parse build layout paint`).

## Current implementation: findings

| Area | Now | Consequence | Plan |
|---|---|---|---|
| Parse | One tag per line. Each attribute is read with `$(_markup_attr …)`, about 27 subshells per `<pane>` line ([tui_markup.sh:358-381](../../lib/markup/tui_markup.sh)) | Cold loads are slow; multi-line tags are impossible | One regex tokenizer with no forks → node store (A) |
| Parse state | Special-case stash arrays per feature (`_TUI_MARKUP_GRID_*`, `_TABS_*`, `_FIXED_*`, `_PENDING` strings) | Every new container type needs new globals | Node store holds children; the stash arrays are deleted |
| Cache | Wraps every `tui.*` builder and eval-replays the recorded calls ([tui_cache.sh:159](../../lib/markup/tui_cache.sh)) | 30+ wrapped functions have to be kept in sync by hand | Serialize the built state with `declare -p` and source it in one step. The wrapper list goes away |
| Layout | Weight integer division, and the last child absorbs rounding. `max_*` clamps leave gaps that aren't redistributed ([tui.sh:498](../../lib/tui.sh)) | Uneven splits; `weight="99"` hacks | Measure/arrange with units and largest-remainder distribution (B) |
| Widget geometry | Widgets are 1 row high except textarea/list/table; there's no widget height, no `min_height` and only `min_width` ([tui.sh:1220](../../lib/tui.sh)) | Forms need helper panes | Widgets are nodes in the same size model |
| Render | Full frame built inside `buf="$( … )"` ([tui.sh:1801](../../lib/tui.sh)); `_draw_ids_now` also uses a subshell | One fork per frame and per hover. State written during a render is lost (see the comment at `tui.render`) | Paint into a global display list, then flush |
| Borders | The glyph `case` is duplicated in `_draw_pane` and `_draw_pane_border` | Adding a new style means editing two places | Line canvas + one glyph table (D) |
| Overlays | Function registry, fully redrawn after every render ([tui_modal.sh](../../lib/chrome/tui_modal.sh)) | No z-order, clipping or damage tracking | Layers (F) |
| Hit test | Linear scan over all widgets, calling `_widget_pos` for each ([tui.sh:2061](../../lib/tui.sh)); fast path exists only for panes | O(widgets) per mouse event | Per-row interval index (E) |
| Scrollbar | Hit only at `mx == col+w-1` ([tui_input.sh:581](../../lib/input/tui_input.sh)); scrolls only `tui.output` content | Hard to hit; widgets can't scroll | Zone in the hit index (E), widget scrolling (G) |
| Focus | `_TUI_FOCUSABLE` in declaration order; `tui.focus` looks up the index linearly | No ordering, groups or scopes | Sorted focus list + id→index map (H) |
| ANSI width | `awk` pipe per measurement ([tui.sh:2004](../../lib/tui.sh), `:2600`) | Forks while streaming | Store styled spans (sgr, text) so width is `${#text}` |

## Performance techniques (bash-only)

- **Struct-of-arrays node store.** Integer node ids and parallel indexed arrays (`_N_TYPE[n]`, `_N_PARENT[n]`, `_N_KIDS[n]`), with attributes in one assoc keyed `n.attr`. This is cache-friendly, lookups are O(1), and one `declare -p` serializes it all.
- **Compile once.** Parse → expand → patch → validate runs once. The build output is dumped with `declare -p` and sourced on later visits, keyed by the existing mtime signature. `dabt build` can precompile at install time.
- **Parallel warm-up behind the splash.** The D.A.B.T splash stays: it's the framework's identity, especially for third-party apps. Stale pages build in a worker pool while it shows (one background subshell per page, capped at the core count). Shared themes and includes are parsed once before forking, and writes are atomic (tmp file + `mv`). The app launches only after every page is cached; nothing warms after launch. When nothing is stale there's no splash.
- **Retained mode + dirty flags.** Mutations set `_DIRTY[n]`; layout reruns only on subtrees whose constraints changed, and paint runs only on dirty nodes and the damage rects they leave behind.
- **Display list.** Paint emits `(row col sgr text)` tuples into global arrays. Clipping to a pane or damage rect is plain substring on text that contains no ANSI codes. Styles are interned SGR strings computed once per `(node,state)` when the class is applied.
- **Painter's algorithm with layers.** For each damage rect, repaint the intersecting nodes bottom-to-top in z-order, each clipped to the rect. Floating panes need exactly this.
- **Row diff.** Keep the previous composed frame per row and write only rows that changed (common prefix/suffix trimming is optional). The write is still one flush wrapped in DEC 2026 sync output (already in place).
- **Frame scheduler.** At most one flush per loop iteration. Input bursts are coalesced (already true for mouse motion and wheel), and there's `tui.frame.request` for ticks.
- **Spatial hit index.** Rebuilt after layout: `row → "c0 c1 node"` intervals sorted by z. A hit test is one row lookup plus a short scan. Scrollbars, dividers, handles and hitboxes are ordinary entries.
- **Constraint layout.** Constraints go down and sizes come up in one pass (Flutter/Yoga-style), integer-only, with largest-remainder rounding. Measurements are memoized per `(node,w,h)`.
- **awk only for bulk ANSI text** (scroll viewports). Batch all dirty viewports into one awk call per frame. A persistent `coproc` awk worker is optional and gated behind a benchmark, since bash supports only one coproc well.
- **Virtualized scrolling.** Offscreen children of a scroll pane are never measured beyond their cached size, and never painted.

## Code reuse map

| Feature | Built from | New code |
|---|---|---|
| row/col/grid/flex/flow/dock | split + size units | desugar table + wrap pass |
| fused panes, border styles | line canvas | glyph table |
| divider/corner resize, collapse, scrollbar, hitbox | hit index + size override | zone kinds |
| floating, detach/dock, modal, popup, tooltip, toast, zoom | layer | flags |
| include, template, component, for/if, addon, factory | node ops | op tags |
| defaults, CSS, class, style, reactive, bind | cascade resolver | expression compiler |
| keep_focus, keep_value, persist, shells, reset | page-state store | none |
| validation (tab order, hitboxes, scripts, refs) | existing rule registry | rules |
| tags, widgets, engines, validators, hooks | one `tui.register` | none |

## File impact

**New** (small, one concern each):

| File | Role |
|---|---|
| `lib/markup/tui_parse.sh` | tokenizer → node store |
| `lib/markup/tui_node.sh` | node store, selectors, node ops |
| `lib/markup/tui_build.sh` | tag registry dispatch (replaces the `case` in `tui.load`) |
| `lib/layout/tui_layout.sh` | measure/arrange, units, desugar |
| `lib/render/tui_paint.sh` | display list, damage, clipping, row diff, flush |
| `lib/render/tui_canvas.sh` | line canvas + junction table |
| `lib/input/tui_hit.sh` | hit index, zones, drag state machine |
| `lib/input/tui_focus.sh` | order, groups, scopes |
| `lib/chrome/tui_layer.sh` | layers, float, detach/dock |
| `lib/state/tui_store.sh` | page state, reactive graph, bind |
| `tools/t.sh` | in-process unit test runner |
| `tests/unit/*.t.sh` | unit tests |

**Changed**:

| File | Change |
|---|---|
| `lib/tui.sh` | layout, render, hit and focus move out; widget constructors become node inserts; should shrink substantially |
| `lib/state.sh` | node-store tables replace most `_TUI_P_*`/`_TUI_W_*` |
| `lib/markup/tui_markup.sh` | thin façade (`tui.load`, `tui.goto`); stash arrays removed |
| `lib/markup/tui_cache.sh` | `declare -p` snapshot; wrapper list removed |
| `lib/markup/tui_validate*.sh` | new rules, script collision diff |
| `lib/style/tui_style.sh` | selectors, variables, layers, `@extend`, layout props |
| `lib/input/tui_input.sh` | click/drag/scrollbar go through the hit index |
| `lib/widgets/*.sh` | `measure`/`paint` interface; `_widget_pos` special cases removed |
| `lib/chrome/tui_modal.sh` | becomes a layer preset |
| `share/tui.xsd` | generated |
| `docs/guide/markup.md` | updated |

## TDD

- **Two tiers.**
  - `tests/unit/`: pure logic, no terminal, runs in-process under `tools/t.sh`.
  - `tests/*.bats`: existing integration tests (install, update, packaging) stay as they are.
- **Why a custom runner:** bats forks at least one process per test (tens of ms each), which rules out < 200 ms per 100 tests.
- **Runner rules (`tools/t.sh`, pure bash):**
  - Source `lib/` once. Every `t_*` function is a test.
  - Reset state between tests by restoring a `declare -p` snapshot taken after load, or by calling the node-store reset.
  - Assertions (`eq`, `ok`, `match`) are functions that increment counters. No subshells, no temp files, no sleep.
  - Output comes from the paint layer's display list and frame rows, compared against inline golden strings. That is the same buffer the real renderer flushes.
  - Fail the run if the suite is over budget (> 2 ms/test average). `-k PATTERN` runs a subset.
- **What gets tested headless:**
  - parse → node tree
  - expansion and addon ops
  - cascade results
  - layout rects
  - line-canvas glyphs
  - hit-index lookups (including the 3-column scrollbar)
  - focus order and warnings
  - page-state save and restore
  - expression evaluation (`??` truth table)
  - validator messages
  - golden frames for small pages
- **Per feature:** failing test → minimal implementation → delete the superseded code → the suite stays under budget.

## Phases

Stages, tasks, definitions of done and hard gates: [markup-v2-implementation-plan.md](markup-v2-implementation-plan.md).

## Open questions

- Is the `coproc` awk worker worth it compared with one batched awk call per frame? Decide by benchmark in phase 3.
- Unicode cell width (CJK, emoji): add a minimal wcwidth table, or document ASCII/BMP-narrow only?
- Disk persistence format: `declare -p` (fast, but it's code that gets sourced) or a data-only key/value file? Loading from `TUI_HOME` is a trust boundary.
- Selector engine scope for `ref=` and CSS: limit it to `#id`, `.class`, `tag` and `>` unless a real need shows up.
