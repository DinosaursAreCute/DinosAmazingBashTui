# Concept: Markup v2 implementation plan

| | |
|---|---|
| Status | Draft: plan, not started |
| Scope | [markup-v2-roadmap.md](markup-v2-roadmap.md) (section letters A–M refer to it) |
| Rules | Bash 5 + POSIX only · TDD · least code · measurable · host-independent tests |

## Status index

Status: `todo` · `wip` · `done` · `blocked`. Update the row when a task changes state; read a task with `sed -n '/^### 2A/,/^### 2B/p'`.

| Task | Owner | Effort | Status |
|---|---|---|---|
| 0.1 Test runner + gate | `tools/t.sh`, `tools/gate.sh` | medium | done |
| 0.2 Measurement | `lib/perf.sh`, `tools/bench/` | medium | done |
| 0.3 Paint-to-buffer + frame dump | `lib/render/tui_emit.sh`, `tools/frame.sh` | medium (conversion: low) | done |
| 0.4 Registry + style contracts | `lib/tui_registry.sh` | medium | done |
| 0.5 Node store | `lib/markup/tui_node.sh` | medium | done |
| 1.1 Tokenizer | `lib/markup/tui_parse.sh` | medium | done |
| 1.2 Build via registry | `lib/markup/tui_build.sh` | medium | done |
| 1.3 Snapshot cache | `lib/markup/tui_cache.sh` | medium | done |
| 1.4 Parallel warm-up | `lib/markup/tui_cache.sh` | medium | done |
| 2A Layout | `lib/layout/tui_layout.sh` | medium | todo |
| 2B Paint + canvas | `lib/render/tui_paint.sh`, `tui_canvas.sh` | medium | todo |
| 2C Hit + focus | `lib/input/tui_hit.sh`, `tui_focus.sh` | medium | todo |
| 2D Node ops | `lib/markup/tui_ops.sh` | medium | todo |
| 3A Fused/resize/collapse | `lib/layout/tui_frame.sh` | medium | todo |
| 3B Layers | `lib/chrome/tui_layer.sh` | medium | todo |
| 3C Scroll widgets | `lib/layout/tui_scroll.sh` | medium | todo |
| 3D Page state | `lib/state/tui_store.sh` | medium | todo |
| 4.1 Cascade | `lib/style/tui_cascade.sh` | medium | todo |
| 4.2 Reactive | `lib/state/tui_reactive.sh` | medium | todo |
| 4.3 CSS lint | `lib/style/tui_style_lint.sh` | medium | todo |
| 5A Script analysis | `lib/markup/tui_scripts.sh` | medium | todo |
| 5B Semantic lint | `lib/markup/tui_validate_rules.sh` | low | todo |
| 5C XSD + dev tools | `tools/gen_xsd.sh`, `lib/chrome/tui_inspector.sh` | medium | todo |
| 6.x Extensions | one file each | low–medium | todo |
| 7 Release | `dabt migrate`, changelog | low | todo |

Orchestration (stage start, gate review, cross-track decisions) runs at high effort. Docs entries, XSD lines and rule lines are low-effort work.

## How this plan is built

- **Stages run in order.** Tracks inside a stage are independent of each other and can run in parallel, in any order.
- **One task, one owner file.** Each task names the file it creates or owns and the few other files it may touch. When a task needs something outside that list, it belongs in another task.
- **Strangler pattern.** A new module is written next to the old code, then the old function body becomes a one-line delegate, then the old code is deleted. All three steps happen in the same task, so no task leaves two live implementations behind.
- **A single seam in `lib/tui.sh`.** Tasks change `tui.sh` only by replacing a function body with a delegate or deleting it. Logic doesn't get added to `tui.sh`.
- **Docs travel with the code.** A task isn't done until its API entries, guide section, XSD entries and validator rules are updated. There's no docs stage at the end.
- **Tests first.** Every task starts with failing unit tests in its own file (`tests/unit/<module>.t.sh`).

## Global hard gates (checked at the end of every stage)

| Gate | Check |
|---|---|
| G1 Tests | `bats tests/ tests/dapk/` and `tools/t.sh` pass |
| G2 Test speed | Unit suite < 200 ms per 100 tests, enforced by the runner |
| G3 Performance | `tools/bench/run.sh --compare baseline` shows no bench more than 5 % slower in mean; the stage's target benches improve |
| G4 Frames | Golden frames of every `share/demo/*.xml` page and of DABT_someApp are identical, unless the stage changes them on purpose (changes are reviewed and re-recorded) |
| G5 Docs | `tools/gen_api_docs.sh --check` passes; guide and XSD are updated for new tags and attributes |
| G6 Forks | Fork counter on hot paths (input, layout, paint, flush) = 0 in benches |
| G7 Visual | Demo and DABT_someApp checked in a real terminal (kitty + one other) |
| G8 Code size | Net `lib/` LOC reported per stage; any growth is justified by features that shipped |

A stage whose gates fail doesn't close, and the next stage doesn't start.

---

## Stage 0: Groundwork

Sequential, blocks everything. No user-visible change.

### 0.1 Test runner
- **Owner:** `tools/t.sh` (new). **Also touches:** `tests/unit/` (new).
- **Tasks:**
  - Write an in-process runner: source `lib/` once; every `t_*` function is a test; assertions `eq`, `ok`, `match`; `-k PATTERN`.
  - Isolate the host: `LC_ALL=C`, `TZ=UTC`, `HOME`/`TUI_HOME`/`XDG_*` pointed at a runner root, and a fixed terminal size.
  - Reset state before each test by restoring the snapshot taken after load.
  - Add a clock variable for logic under test.
  - Fail the run when it exceeds the budget.
  - Port the pure-logic cases from `tests/layout.bats`.
  - `tools/gate.sh [G1..G8]`: runs every hard gate and prints **only failures**, one line each (`gate<TAB>file:line<TAB>message`), exit 0 when clean. It is the single command for stage reviews.
  - Runner output: one summary line (`pass fail ms`), plus one line per failure.
- **Done when:** 100 trivial tests run in < 200 ms; a single test runs alone with `-k` and passes; the suite passes with `HOME=/nonexistent`.

### 0.2 Measurement
- **Owner:** `lib/perf.sh` (new). **Also touches:** `lib/tui.sh` (source line), `tools/bench/` (new).
- **Tasks:**
  - `_tui_perf.begin`/`end NAME` spans using `$EPOCHREALTIME`, in ring buffers; with tracking off, a span costs one `(( ))`.
  - Counters: forks, full renders, cache hit/miss, nodes painted, bytes flushed.
  - `tui.perf.report` and `TUI_PERF_LOG`.
  - Benches for the current code: cold page load, warm page load, full render, hover redraw, focus move, mouse hit, resize relayout, scroll burst.
  - Record `tools/bench/baseline.txt`.
- **Done when:** the baseline is committed; spans wrap parse, build, layout, render, flush and dispatch in the current code; tracking off costs < 1 % in benches.

### 0.3 Paint-to-buffer
- **Owner:** `lib/render/tui_emit.sh` (new). **Also touches:** the draw functions in `lib/tui.sh`, `lib/widgets/*.sh`, `lib/chrome/*.sh`, one file per commit.
- **Tasks:**
  - Add `_tui.emit` and buffer-mode cursor and style helpers, all appending to `_TUI_FRAME` via `printf -v`.
  - Convert every draw path to append. `tui.render` and `_draw_ids_now` stop using `$( )`.
  - `_tui._flush` writes `_TUI_FRAME`.
  - Before converting, record golden frames of every demo page with the current renderer (`tools/t_golden.sh`, run once).
  - `tools/frame.sh PAGE [COLS]x[ROWS]`: headless render of a page to plain text (ANSI stripped; `--sgr` keeps styles). Used for visual checks without a terminal and for golden frames.
- **Done when:** golden frames are byte-identical; no `$( )` remains in render paths; the bench shows a gain on full render and hover redraw; the state-lost-in-subshell workaround in `tui.render` is deleted.
- This is the largest mechanical task. It unlocks headless frame tests for every later stage.

### 0.4 Registry primitive
- **Owner:** `lib/tui_registry.sh` (new).
- **Tasks:**
  - `tui.register KIND NAME FN…` and `tui.registered KIND NAME`, which returns handlers through a global.
  - Kinds: `tag`, `widget`, `layout`, `validator`, `pseudo`, `expr`, `hook`, `style`.
  - **Style contracts (`style` kind):** each widget type and each chrome element registers the pseudo-states it can enter and the framework classes it draws with. Examples:
    - `button`: `hover focus active disabled`
    - `list`: classes `.list_sel`
    - `table`: classes `.table_head .table_sel`
    - `tabs`: classes `.tab_header .tab_header_compact`
    - `checkbox`: states `checked unchecked`
    - `pane`: `border title focus` (no `hover`)

    One table serves the CSS lint (4.3), the XSD generator (5C) and `tui.class`, instead of the state list hard-coded in `tui.class` and `_tui._find_theme_collisions`.
  - Plugin ownership via `_tui_plugin.own`, so disabling a plugin unregisters its handlers.
- **Done when:** the unit tests cover register, lookup, override order and plugin unregistration; the contracts of every existing widget and chrome element are registered, and `tui.class` reads its state list from them.

### 0.5 Node store
- **Owner:** `lib/markup/tui_node.sh` (new).
- **Tasks:**
  - Struct-of-arrays node table: `_N_TYPE`, `_N_PARENT`, `_N_KIDS`, `_N_ID` and an attribute assoc keyed `n.attr`, plus an id→node map.
  - Operations: create, attr get/set, children, walk, `declare -p` dump/load, reset.
  - No engine changes: the engine keeps its `_TUI_P_*`/`_TUI_W_*` arrays for now.
- **Done when:** dump → reset → load round-trips; a walk over 1 000 nodes is benchmarked.

**Stage 0 gates:** G1–G8. The demo is visually unchanged. The baseline recorded in 0.2 becomes the reference for every later stage.

---

## Stage 1: Parser and build

Depends on 0. One track.

### 1.1 Tokenizer → node store
- **Owner:** `lib/markup/tui_parse.sh` (new).
- **Tasks:**
  - Fork-free regex scan of the whole file (read with `mapfile`/`read -d ''`).
  - Multi-line tags, both quote styles, entities, text content, comments anywhere.
  - Include expansion.
  - Each node records its file and line for error messages.
- **Done when:** every existing page parses to the expected tree; the parse bench is faster than the baseline's cold load; errors report file and line + column (if applicable).

### 1.2 Build via tag registry
- **Owner:** `lib/markup/tui_build.sh` (new). **Also touches:** `lib/markup/tui_markup.sh` (shrinks to a façade).
- **Tasks:**
  - Walk the tree and dispatch each node to its registered tag handler.
  - Move each `case` branch of `tui.load` into a handler. Move the code; don't rewrite it.
  - Nested widgets: a widget's pane is its parent, and its row is inferred from document order.
  - Auto ids for anonymous nodes.
  - Helper tags (`row`, `col`, `spacer`, `divider`, `group`) as an alias table that maps to pane plus attributes.
  - Legacy `pane=`/`row=` still work.
- **Deletes:** `_markup_attr`, `_markup_trim`, every `_TUI_MARKUP_*` stash array and the per-line loop.
- **Done when:** G4 frames are identical for all existing pages; nested-widget and helper-tag unit tests pass; `tui_markup.sh` is under 150 lines.

### 1.3 Snapshot cache
- **Owner:** `lib/markup/tui_cache.sh`.
- **Tasks:**
  - Cache the built engine state as a `declare -p` snapshot and restore it with one `source`, keyed by the existing mtime signature.
  - Keep `<script>` and `on_visit` as recorded dynamic calls.
- **Deletes:** the wrapper list and the eval replay.
- **Done when:** a warm load is faster than the baseline; editing any dependency invalidates the cache (unit-tested with the clock and stamps); no stale cache is served.

### 1.4 Parallel warm-up behind the splash screen
- **Owner:** `lib/markup/tui_cache.sh`. **Replaces:** the single sequential worker in `tui.cache.warm_with_spinner`.
- **The splash screen stays, by design.** The D.A.B.T banner and progress bar are the framework's identity. For third-party apps they are its main exposure, and that is worth a slower first load. The app launches only after **every** stale page is cached. Nothing warms in the background after launch.
- **Why parallel is safe:** each page's snapshot depends only on its own file and its includes, themes and components, so pages can be built in any order and at the same time. Build is headless after 0.3 and 1.2 and sources no `<script>` (those stay recorded dynamic calls), so a worker has no side effects outside its own output file.
- **Tasks:**
  - **Shared dependencies once:** the parent parses shared themes, includes and components before forking. Workers inherit them through fork memory, so nothing is parsed twice.
  - **Worker pool:**
    - One background subshell per stale page.
    - Up to `min(getconf _NPROCESSORS_ONLN, stale pages, TUI_CACHE_WORKERS)` run at once, refilled as workers finish.
    - Workers get stdin/stdout set to `/dev/null`.
  - **Atomic output:** each worker writes `<page>.snap.tmp.$BASHPID`, then `mv` renames it to `<page>.snap` in the same directory. Concurrent app instances race harmlessly, and a crashed worker leaves no partial snapshot.
  - **Splash progress:**
    - The splash counts finished pages as snapshots appear (or through the existing fifo, whichever is simpler once measured) and keeps animating while workers run.
    - Ctrl-C still reaches it and kills the pool.
    - The progress bar is driven by pages completed, not by elapsed time.
  - Only stale pages are queued, using the per-page signature. When nothing is stale, the splash is skipped and the app starts immediately.
  - A worker that fails is reported on the splash, and its page falls back to a normal uncached load. One bad page never blocks the others.
- **Done when:**
  - A unit test proves serial and parallel builds produce byte-identical snapshots.
  - Killing a worker mid-write leaves no `.snap`.
  - The bench shows total warm time scaling with workers (1/2/4/8 recorded), and a full cold warm-up is faster than the sequential baseline.
  - A warm start (nothing stale) shows no splash and loads within G3 of the baseline.
  - After the splash every page is cached: the first visit to any page is a cache hit.

**Stage 1 gates:** G1–G8. The cold warm-up (splash duration) and warm load benches improve. The markup guide documents nesting, multi-line tags and helper tags.

---

## Stage 2: Core engine

Depends on 1. Four independent tracks: each owns its own module and they don't touch each other's files.

### 2A Layout and sizing (roadmap B, the split core of C)
- **Owner:** `lib/layout/tui_layout.sh` (new). **Seam:** `_tui._layout`, `_tui._widget_pos`.
- **Tasks:**
  - Measure/arrange passes; units `cells`, `%`, `fr`, `auto`, `fill`, `clamp()`; `min_*`/`max_*`; largest-remainder distribution; space freed by `max` is redistributed.
  - Widgets become sized children: `width`, `height`, `expand`, `padding`, `margin`, `gap`.
  - Grid and fixed layouts keep producing splits.
  - Memoize by `(node,w,h)`; mark dirty subtrees for incremental relayout.
  - `weight` maps to `fr`.
- **Deletes:** the weight-only split math and the per-type cases in `_widget_pos`.
- **Done when:** unit tests cover rects for every unit and clamp combination; G4 holds for existing pages; the resize-relayout bench is not slower.

### 2B Paint pipeline and line canvas (roadmap D base)
- **Owner:** `lib/render/tui_paint.sh`, `lib/render/tui_canvas.sh` (new). **Seam:** `tui.render`, `_draw_pane`, `_draw_pane_border`.
- **Tasks:**
  - Display list `(row col sgr text)`; dirty flags; damage rects; clipping by substring; per-row diff against the previous frame; one flush per loop iteration (`tui.frame.request`).
  - SGR strings interned per `(node,state)`.
  - Line canvas with one glyph and junction table for all border styles.
  - awk content batched to one call per frame.
- **Deletes:** the duplicated glyph `case`, and direct cursor printing in draw code.
- **Done when:** G4 frames are identical; hover redraw and focus move benches improve; bytes flushed per hover shrink measurably.

### 2C Hit index and focus (roadmap E base, H)
- **Owner:** `lib/input/tui_hit.sh`, `lib/input/tui_focus.sh` (new). **Seam:** `_tui._hit_test`, `_tui._pane_at`, `tui.focus`, `_tui._focus_next`/`_prev`, the scrollbar branch of `tui.action.click`.
- **Tasks:**
  - Per-row interval index rebuilt after layout.
  - Zone kinds: widget, hitbox, scrollbar (3 columns wide / 3 rows high), divider, handle, chevron, title.
  - `hitbox` and `hit_pad`.
  - `focusable`, `tabbable`, `tab_order` (0 first, -1 last, gaps and duplicates warn), `focus_group`, `focus_nav`, `focus_wrap`, `autofocus`, `focus_next`/`focus_prev`.
  - id→index map for focus.
- **Deletes:** the linear widget scan and the linear focus index search.
- **Done when:** hit and focus-order unit tests pass (including the scrollbar edges); the mouse-hit bench is O(1) in widget count (bench at 10 and 500 widgets); the validator warns on tab order gaps and duplicates.

### 2D Node ops and composition (roadmap J)
- **Owner:** `lib/markup/tui_ops.sh` (new). **Also touches:** `tui_build.sh` (registers op tags).
- **Tasks:**
  - Ops: clone, insert (append/prepend/before/after), replace, remove, set, wrap, move.
  - Minimal selectors: `#id`, `.class`, `tag`, `>`.
  - Built on the ops: `<template>`/`<use>`/`<slot>`/`<fill>`, `<component>`, parametrised `<include>`, `<for>`/`<if>`.
  - Addon XML: discovery, priority, id prefixing, `tui.addon.load`/`unload` rebuilding only the affected subtree.
  - Factories rewritten on top of the ops.
- **Deletes:** the factory bookkeeping in `tui.sh`.
- **Done when:** unit tests cover each op, selector and addon conflict; factory API behaviour is unchanged (existing callers pass).

**Stage 2 gates:** G1–G8. Every track has passed its own done criteria. Rerun the benches and record them as the new baseline.

---

## Stage 3: Features on the core

Depends on 2. Independent tracks. The "Uses" line lists the stage 2 modules each track relies on. A track only adds a module or zone kinds; it doesn't restructure stage 2 code.

### 3A Fused panes, resize, collapse (roadmap D, E)
- **Uses:** 2A, 2B, 2C. **Owner:** `lib/layout/tui_frame.sh` (new).
- **Tasks:**
  - `fuse`, `divider`, `divider_class`, `title_pos`, `title_align`, border styles.
  - `resizable`/`handle` drag state machine with keyboard resize mode, `on_resize`, double-click reset.
  - `collapsible`/`collapsed`/`collapse_to`, `<details>`, `<accordion>`, `tui.collapse`, `on_toggle`.
- **Done when:** golden frames cover nested fused panes and mixed borders; drag unit tests respect min/max; collapse restores the previous size.

### 3B Layers: floating and detachable (roadmap F)
- **Uses:** 2A, 2B, 2C, 2D. **Owner:** `lib/chrome/tui_layer.sh` (new). **Seam:** `lib/chrome/tui_modal.sh` becomes a layer preset.
- **Tasks:**
  - Layer stack with z-order; anchors (`screen`/`parent`/`#id`); clamping to the screen.
  - `float`: move, resize, raise on focus, minimize, snap.
  - `detachable`: detach and dock are implemented as the `move` op, with a dock-target layer, `dock_group`, `leave=`, `on_detach`/`on_dock`, `persist="layout"`.
  - Overlay tags: `<window>`, `<modal>`, `<dialog>`, `<popup>`, `<tooltip>`, `<contextmenu>`, `<toast>`; zoom.
  - Focus scopes (trap and restore).
- **Deletes:** the overlay function registry and its full redraw after every render.
- **Done when:** the command palette and dialogs work unchanged on top of layers; golden frames cover overlapping layers; damage repaints only the rect a layer vacated.

### 3C Scrolling widgets (roadmap G)
- **Uses:** 2A, 2B, 2C. **Owner:** `lib/layout/tui_scroll.sh` (new).
- **Tasks:**
  - Content height taken from arranged children; offscreen virtualization.
  - `scroll_into_view` on focus, `tui.scroll.to`, `sticky="top"`, wheel routed to the innermost pane that can still scroll.
- **Deletes:** the output-only special cases in the scroll path.
- **Done when:** a form taller than its pane scrolls with Tab; the bench shows paint cost bounded by the viewport, not by content size.

### 3D Page state and shells (roadmap I)
- **Uses:** 2C, 2D. **Owner:** `lib/state/tui_store.sh` (new).
- **Tasks:**
  - One store keyed `page|id|field`.
  - `keep_focus`, `focus_on_enter`, `keep_value`, `keep_state`, `persist="session|disk"`.
  - `tui.page.reset`, `tui.page.reset_field`, `tui.page.reset_all`, exposed as actions and palette commands.
  - Shells: `shell=` + `<outlet/>`; shell nodes are never torn down.
- **Done when:** unit tests cover save and restore for each widget type; switching pages in a shell is faster than the full `tui.goto` baseline.

**Stage 3 gates:** G1–G8. DABT_someApp is migrated to shells, fused panes and nested widgets as the real-world check; its XML shrinks noticeably.

---

## Stage 4: Cascade and reactivity

Depends on 1, 2B and 2D. One track: everything resolves attributes, so a single owner avoids conflicts.

### 4.1 Attribute cascade (roadmap K)
- **Owner:** `lib/style/tui_cascade.sh` (new). **Also touches:** `lib/style/tui_style.sh` (the parser gains selectors, variables, `@layer`, `@extend` and layout props).
- **Tasks:**
  - One resolver with the roadmap K order.
  - `<defaults>` and inline `style=`.
  - Addon CSS and `tui.theme.add`/`remove`.
  - The result feeds SGR interning (2B) and layout props (2A).
- **Deletes:** per-attribute setters that the cascade now covers (kept as thin public aliases where they are API).
- **Done when:** a precedence unit test covers every layer pair; theme load stays memoized; the warm-load bench is not worse.

### 4.2 Reactive values and binding
- **Owner:** `lib/state/tui_reactive.sh` (new).
- **Tasks:**
  - Expression compiler: `??` (unset, empty or false), ternary, `! && || == !=`, `arr[key]`. Compiled once to a bash snippet, never evaluated at runtime from untrusted input.
  - Dependency graph var → nodes; `tui.state.set` marks dependent nodes dirty and the frame batches the updates.
  - `bind=`; `disabled`, `hidden`, `readonly` and `data-*` on every node.
- **Done when:** a truth-table unit test for `??` and every operator passes; a state change repaints only the dependent nodes (checked with the nodes-painted counter).

### 4.3 CSS validation
- **Owner:** `lib/style/tui_style_lint.sh` (new). **Also touches:** `lib/style/tui_style.sh` (the parser records file:line per rule and declaration).
- **Replaces:** `_tui._find_theme_collisions`. Its title-vs-border check becomes one rule here.
- **Inputs:** the parsed rules with source positions, the effective cascade (default theme + app themes + overlay + addon CSS), the style contracts (0.4) and class usage from the node store.
- **Severity:**
  - `error`: blocks strict mode and the validation gate.
  - `warning`: logged and shown by `dabt lint`, plus the existing validation notice.
  - `info`: `dabt lint --verbose` only.
- **Rules:**

  | Rule | Severity |
  |---|---|
  | Syntax: unclosed block, missing `;`, empty selector | error |
  | Unknown property, invalid colour (neither a name nor `#RRGGBB`), unknown `mods` value, unknown pseudo-state, undefined `var(--x)`, `@extend` of a missing class, `@extend` cycle | error |
  | **Missing interactive state:** a class used on an element whose contract allows `hover`/`focus`/`active`/`checked` defines the normal state but not that one. Reported per missing state, e.g. `.save_btn used on <button> has no :hover`. `focus` missing on a focusable element is reported first | warning |
  | **Unreachable state:** the pseudo-state is not in the contract of any element using the class, e.g. `:hover` on a class only used on panes | warning |
  | **Missing framework classes:** the effective cascade lacks a class that a widget or chrome element on the page draws with (e.g. a page has a `<table>` but nothing defines `.table_head`), or a common class the framework ships (`.panel`, `.field_label`, `.footer`, `.dialog*`, `.toast*`, `.palette*`, button variants) | warning |
  | **Theme completeness:** a theme under `themes/` doesn't define every class and state that the default theme defines. Reported as a coverage list per theme | warning |
  | Class used in markup but defined nowhere | warning |
  | Invisible text: `fg` equals `bg` in any resolved state | warning |
  | Title blends into the border ring when focused (the existing collision rule) | warning |
  | A state identical to normal, e.g. `:hover` with no visible change | info |
  | A duplicate rule in the same file; a declaration fully shadowed by a later layer | info |
  | A class defined but never used by any page | info |
- **When it runs:** only when a stylesheet or page is actually parsed. A memo hit skips it, as today. During the splash warm-up (1.4), each worker lints its own page and the splash shows a one-line summary. `dabt lint --theme FILE` runs the theme-completeness report on its own.
- **Output:** `file:line: severity: rule-id: message` plus a fix hint (e.g. `add .save_btn:hover { … }`). Messages go to `tui.log` and to the lint CLI from the same array.
- **Done when:**
  - Every rule has one failing and one passing inline CSS fixture.
  - The shipped default theme and every bundled theme produce no errors, and their warnings are either fixed or listed on purpose.
  - DABT_someApp's `theme.css` is linted with no false positives.
  - Lint adds no measurable time to a warm load (it doesn't run on memo hits).

**Stage 4 gates:** G1–G8.

---

## Stage 5: Validation and tooling

Depends on 4. Independent tracks. Each feature added its own validator rules in its own stage; this stage covers only the cross-cutting tools.

### 5A Script analysis (roadmap L)
- **Owner:** `lib/markup/tui_scripts.sh` (new).
- **Tasks:**
  - Multiple `<script>` tags, globs, `ns=`.
  - A `declare -F` and globals diff around each source, reporting collisions, `tui.*` overrides, `_TUI_*` writes, functions outside the declared `ns` and undeclared shared globals.
- **Done when:** unit tests with inline script snippets produce each diagnostic.

### 5B Semantic lint
- **Owner:** `lib/markup/tui_validate_rules.sh`.
- **Tasks:**
  - The remaining roadmap L rules: dangling refs, duplicate ids after expansion, keybinding conflicts, undefined classes, undefined expression variables, `keep_focus` targets.
  - `dabt lint` and strict mode, covering markup, scripts (5A) and CSS (4.3) in one report.
- **Done when:** every rule has a failing and a passing fixture; lint runs on all demo pages and DABT_someApp without false positives.

### 5C Generated schema and developer tools
- **Owner:** `tools/gen_xsd.sh`, `lib/chrome/tui_inspector.sh` (new).
- **Tasks:**
  - Generate the XSD from the tag, attribute and enum registries.
  - Inspector layer showing ids, rects, hitboxes, tab order and perf spans.
  - `dabt dev` hot reload and `dabt fmt`.
- **Deletes:** the hand-written `share/tui.xsd`.
- **Done when:** a bats test fails on a stale XSD; hot reload keeps page state.

**Stage 5 gates:** G1–G8.

---

## Stage 6: Extensions

Depends on 5. Every item is independent: one registration plus one file.

| Item | Owner | Registers |
|---|---|---|
| flex / flow (wrap) | `lib/layout/engines/flex.sh` | `layout flex`, `layout flow` |
| dock | `lib/layout/engines/dock.sh` | desugar to splits |
| grid spans / areas / auto_fill | `lib/layout/engines/grid.sh` | extends grid |
| responsive (`hide_below`, `split_below`, `<when>`, `attr.sm`) | `lib/layout/tui_responsive.sh` | resolve-time pass |
| overflow / priority | `lib/layout/tui_overflow.sh` | layout pass |
| each new widget (tree, menu, radio, slider, number, date, log, markdown, chart, statusbar, breadcrumb, badge) | `lib/widgets/<name>.sh` | `widget <name>` |
| data sources (`items_from`, `src=csv`, `<column>`) | `lib/widgets/tui_datasource.sh` | shared by list, table, select, tree |

- **Done when (per item):** unit tests, a golden frame, an API/guide/XSD entry and a bench if the item sits on a hot path.

**Stage 6 gates:** G1–G8 after each merged item.

---

## Stage 7: Release

- A migration tool (`dabt migrate`) that turns `pane=`/`row=` placement into nesting and `weight` into `fr`, with a dry-run diff.
- Deprecation warnings for legacy forms.
- `schema_version` on `<tui>`.
- Changelog and a release note with before/after bench tables.
- Update the roadmap status.

**Final gates:** G1–G8; all demo pages and DABT_someApp run on v2 syntax; every stage 0 baseline bench has improved or held.

## Dependency overview

```
0 Groundwork ─▶ 1 Parser/Build ─▶ 2A Layout ─┐
                                  2B Paint  ─┼─▶ 3A Fused/Resize/Collapse
                                  2C Hit/Foc ─┤   3B Layers (also 2D)
                                  2D Node ops ┘   3C Scroll widgets
                                                  3D Page state (2C, 2D)
                                  2B + 2D ─────▶ 4 Cascade/Reactive ─▶ 5 Validation/Tools ─▶ 6 Extensions ─▶ 7 Release
```
