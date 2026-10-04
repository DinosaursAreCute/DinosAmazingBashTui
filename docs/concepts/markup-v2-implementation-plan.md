# Concept: Markup v2 implementation plan

| | |
|---|---|
| Status | IN PROGRESS |
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
| 2A Layout | `lib/layout/tui_layout.sh` | medium | done |
| 2B Paint + canvas | `lib/render/tui_paint.sh`, `tui_canvas.sh` | medium | done |
| 2C Hit + focus | `lib/input/tui_hit.sh`, `tui_focus.sh` | medium | done |
| 2D Node ops | `lib/markup/tui_ops.sh`, `tui_compose.sh`, `tui_addon.sh`, `tui_refresh.sh` | medium | done |
| 3A Fused/resize/collapse | `lib/layout/tui_frame.sh`, `tui_resize.sh`, `tui_collapse.sh` | medium | done |
| 3B Layers | `lib/chrome/tui_layer.sh` | medium | todo |
| 3C Scroll widgets | `lib/layout/tui_scroll.sh` | medium | done |
| 3D Page state | `lib/state/tui_store.sh`, `lib/markup/tui_shell.sh` | medium | wip (store, reset, disk, focus done; shells unverified) |
| 4.1 Cascade | `lib/style/tui_cascade.sh` | medium | todo |
| 4.2 Reactive | `lib/state/tui_reactive.sh` | medium | todo |
| 4.3 CSS lint | `lib/style/tui_style_lint.sh` | medium | todo |
| 5A Script analysis | `lib/markup/tui_scripts.sh` | medium | todo |
| 5B Semantic lint | `lib/markup/tui_validate_rules.sh` | low | todo |
| 5C XSD + dev tools | `tools/gen_xsd.sh`, `lib/chrome/tui_inspector.sh` | medium | todo |
| 6.x Extensions | one file each | low–medium | todo |
| 7 Release | `dabt migrate`, changelog | low | todo |

Orchestration (stage start, gate review, cross-track decisions) runs at high effort. Docs entries, XSD lines and rule lines are low-effort work.

## Progress (2026-10-03)

Done and unit-tested (suite: 500 pass, 0 fail). Gates G1–G8, benches, golden frames and visual checks are run by hand, not by the implementer; see "Owed" below.

| What | Where | Notes |
|---|---|---|
| 2D closed: factories | `lib/markup/tui_factory.sh`, state in `lib/state.sh` | Moved out of `lib/tui.sh` (-157 lines); a shared `make` helper replaces four copies of the id-and-track code. API unchanged. They stay imperative (they build engine state at runtime, not nodes). |
| 3C: scrolling widgets | `lib/layout/tui_scroll.sh` | Content height, offset applied in `_tui._widget_pos` (part of its cache key), hit zones clipped to the content rect, scrollbar for widget panes (shared with `tui.output` panes), `scroll_into_view` on focus, `tui.scroll.to`, `pin="top"`, wheel routing (widget under the pointer, then its pane); a widget taller than the rest of the viewport is cut at the bottom edge. The Scrolling demo page (`scrolling.xml`) is the showcase: widget form + `tui.scroll.to` buttons + two `tui.output` viewports. |
| Nested widgets: engine fix | `lib/markup/tui_build.sh` | Nested `textarea`, `password`, `select`, `progress`, `list` and `table` were silently dropped ("missing id or pane"); only label/button/input/checkbox worked nested. Fixed, with a regression test. |
| Demo pages on nested widgets | `share/demo/*.xml` | 16 pages converted (see "Demo migration"). New page `scroll_form.xml`, nav entry "Scroll form". |
| Tooling | `tools/page_state.sh` | Headless dump of the built engine state (panes, widgets, tab order). `diff` of two spellings of one page proves a markup rewrite changed nothing the engine sees. Reusable for `dabt migrate` (stage 7). |

**Deviations from the stage 3 spec**
- Pinned rows use `pin="top"`, not `sticky="top"`: `sticky` already names the input focus policy (`_TUI_W_STICKY`).
- Public API added: `tui.scroll.to`, `tui.pin`, `tui.pane_scroll_into_view` (each with an API entry).

**Demo migration.** A page counts as migrated when `tools/page_state.sh` is identical before and after, or identical except `_TUI_W_ORDER` (same widgets, other order).
- Identical: case_study, docu, features, home, keys, settings, styles, scrolling, widgets (+ monitor apart from its live clock label).
- Tab order changed (nested widgets follow pane order; the first-focused widget may differ): components, components_fit, components_theme, debug, debug_lab.
- Not converted: `_templates.xml` (its widgets target panes that live in each page), `compose.xml` (no legacy widgets), `share/defaults/pages/*.xml` (not demo pages).

**Owed by the user (not run by the implementer)**
- Golden frames (G4): re-record the five pages whose Tab order changed, and every demo page (the nav gained "Scroll form").
- G3 benches: paint cost on `scroll_form.xml` bounded by the viewport; no regression elsewhere.
- Visual check (G7) of 3C: Tab through `scroll_form.xml`, wheel and pinned heading, scrollbar thumb, click after scrolling, the Scrolling demo's `tui.output` panes unchanged.
- Known and left alone by request: `tests/unit/cache.t.sh` (replay re-reads the real terminal size) and two `updater.bats` tests fail only with a controlling tty, because `tui.update.cli` silences stderr for good via a bare `exec 3<… 2>/dev/null`.

## Progress (2026-10-04)

Suite at the last verified run: 767 pass, 0 fail (before the shell work started). `tools/gen_api_docs.sh --check` and the validator on `workspace.xml` and `widgets.xml` were clean.

| What | Where | Notes |
|---|---|---|
| 3A fused panes and titles | `lib/layout/tui_frame.sh` | `fuse`, `divider`, `divider_class`, `title_pos`, `title_align`; the title of a lower fused pane is drawn on the shared line. |
| 3A resize | `lib/layout/tui_resize.sh` | `resizable`, `handle`, `on_resize`; mouse drag, double-click reset, `alt+r` keyboard mode with a `[resize]` marker, held-arrow coalescing. The last pane of a split resizes by its leading edge. Hover style on handles and dividers (`.resize_handle`). |
| 3A collapse | `lib/layout/tui_collapse.sh` | `collapsible`, `default`, `collapse_to`, `collapsed_text`, `on_toggle`, `collapse_key`, `collapse_class`, `<details>`, `<accordion>`; a two-cell direction button on the border corner of the moving edge (`.collapse_button`, `:hover`, `:collapsed`); `alt+c`. |
| 3A showcase | `share/demo/workspace.xml` | An on-call console replaces `styles.xml`; nav entry `btn_workspace`. |
| 3D store and reset | `lib/state/tui_store.sh` | One `page\|id\|field` store (value, cursor, scroll, sel, collapsed, size, focus); `keep_value`, `keep_collapsed`, `keep_size`, `keep_state`; `tui.page.reset`, `reset_field`, `reset_all`, `resettable`; `alt+shift+r` and a footer item. |
| 3D disk and focus | `lib/state/tui_store.sh` | `persist="disk"` writes `TUI_HOME/state/store` (data-only, never sourced, 0600); `keep_focus`, `focus_on_enter`. |
| Profiler | `tools/profiler/dprof/scenarios.py`, `tools/bench/run.sh` | Scenarios `workspace`, `state`, `scrollform`; micro-benches `resize_drag_step`, `collapse_toggle`, `hit_with_handles`, `hover_zone_move`, `store_save_restore`. |
| Test runner | `tools/t.sh` | `_t_fixture NAME FUNC` builds a page once per run and replays its globals. |

**Deviations from the stage 3 spec**
- `corner` handles move the nearest ancestor edge and have no edge to move on a pane that is last in every split; the last pane resizes by its leading edge instead.
- The collapse control is a separate two-cell button on the frame corner, not a chevron in the title. `collapse_to="rail"` needs a button with `collapsed_text`.
- Enter/Space on a focused chevron is not implemented; `alt+c`, a click and `collapse_key` toggle.
- `alt+shift+r` is bound to `tui.action.page_reset`.
- `persist="disk"` implies the keep flags unless `keep` is explicitly `false`; values equal to the first-build default are not written; `tui.store.get` sees disk entries only after the page is restored; the first-build defaults are captured once, on first restore.
- `lib/tui_home.sh` uses the installed defaults only when their `install.meta` version equals `TUI_VERSION` (an older install used to shadow newer keybinds and theme classes). No unit test covers the version rule.
- The unit speed budget forced several multi-relayout tests into the integration tier (`ti_*`).

**Unverified: shells (3D-3).** `lib/markup/tui_shell.sh` and hooks in `tui.sh`, `tui_build.sh` (a `tag.pane` child loop moved into `_tui_build.pane_kids`, the `<outlet>` tag), `tui_markup.sh`, `tui_cache.sh` and `tui_store.sh` were written and never run. `tui_shell.sh` is sourced from `tui.sh`, so a syntax error there breaks every page. Not done: `tests/unit/shell.t.sh`, validator rules, XSD, the guide section, the `tui.shell.file` API entry, `share/demo/_shell.xml` and the page conversion, the `tui.page.refresh` fallback, shell-first cache warm-up and the timing against a full `tui.goto`. First step: `bash -n` on the six files, then `tools/t.sh` (expect 767 pass).

**Owed by the user (not run by the implementer)**
- Golden frames (G4): re-record every demo page (the nav changed; the update banner is stored in the frames, so `t_golden.sh --check` reported every frame as changed before this work).
- G3 benches: `tools/bench/run.sh --compare tools/bench/baseline.txt`; `baseline.txt` is not regenerated. The old `mouse_hit` bench probably measures an empty index because `tui.load` resets the terminal size to 0 without a tty.
- G7 visual check in a real terminal: Workspace page (shared border of the fused logs, divider hover and drag, the collapse button arrows, `alt+r` mode), the scroll form, and no stray glyphs after a divider drag.
- `bats tests/` already failed at HEAD (update banner, tty).

**Measured costs to improve** (from the new micro-benches): hover between two zones about 38 ms, collapse toggle about 45 ms, one resize step about 32 ms (about 52 ms with the full frame; render dominates: the junction pass about 18 ms, widgets about 13 ms), saving and restoring 30 inputs about 95 ms. Hit lookup is 0.15 ms.

**Next:** finish 3D-3 (shells), then the performance items above, then 3B (its `persist="layout"` needs the 3D store). The comment sweep covers the 3A files; the 3D files, `tui_markup.sh`, `tui_build.sh`, `tui_cache.sh`, `tui_footer.sh`, the validator rules and the store tests still need it. `DABT_someApp` is migrated at the very end as the user's validation step, not as part of any feature.

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
| G2 Test speed | Unit (`t_*`) suite < 200 ms per 100 tests; integration (`ti_*`, page build/replay) exempt from the flat budget, capped at 60 ms per test on average (`TUI_T_INTEG_MS` sets the total); both enforced by the runner |
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
  - Keep `<script>`, `on_visit`, `<theme src>` and every build-time `tui.class ID CLASS` call as recorded dynamic calls, replayed fresh on every cache hit - a theme switch (`tui.theme.set`/`.pick`) must reach an already-cached page's actual rendered colors, not just its class table.
- **Deletes:** the wrapper list and the eval replay.
- **Done when:** a warm load is faster than the baseline; editing any dependency invalidates the cache (unit-tested with the clock and stamps); no stale cache is served; switching the app-wide theme overlay recolors an already-cached page on its next replay, including per-widget baked style (`_TUI_STYLE_*`), not only the class table (`_TUI_CLASS_*`) - unit-tested, since this bypasses the mtime signature entirely and a naive fix silently stops at the class table.

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
- **Done when:** hit and focus-order unit tests pass (including the scrollbar edges); a mouse hit costs the zones crossing the pointer's row, not the widgets on the page (bench at 10 and 500 widgets in one column; the index is rebuilt once per layout); the validator warns on tab order gaps and duplicates.

### 2D Node ops and composition (roadmap J)
- **Owner:** `lib/markup/tui_ops.sh` (new). **Also touches:** `tui_build.sh` (registers op tags).
- **Tasks:**
  - Ops: clone, insert (append/prepend/before/after), replace, remove, set, wrap, move.
  - Minimal selectors: `#id`, `.class`, `tag`, `>`.
  - Built on the ops: `<template>`/`<use>`/`<slot>`/`<fill>`, `<component>`, parametrised `<include>`, `<for>`/`<if>`.
  - Addon XML: discovery, priority, id prefixing. **Delivered** (`lib/markup/tui_addon.sh`). Load and unload while the app runs are `tui.page.refresh` (`lib/markup/tui_refresh.sh`): it re-applies the addons on disk and rebuilds only the panes whose signature changed, within the 100 ms page-switch budget; `tui.addon.load`/`unload` as separate calls were not needed.
  - Factories rewritten on top of the ops.
- **Deletes:** the factory bookkeeping in `tui.sh`.
- **Done when:** unit tests cover each op, selector and addon conflict; factory API behaviour is unchanged (existing callers pass).
- **Status:** ops, selectors, templates, components, loops, conditions, parameterised includes, addons and `tui.page.refresh` are done and tested (`ops`, `compose`, `addon`, `refresh` unit tests; a refreshed page equals a full load); the Compose demo page (`share/demo/compose.xml`) exercises all of it. Also delivered next to this task: background jobs with a spinner (`lib/tui_job.sh`, `tui.page.rebuild`). Factories: moved into `lib/markup/tui_factory.sh` with their state in `lib/state.sh`, bookkeeping removed from `lib/tui.sh`; they stay imperative (they build engine state at runtime, not nodes), so they were not rebuilt on the node ops.

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
- **Agreed details:**
  - `resizable="x|y|both"` works on any pane (normal, fused or layer). `handle="corner|edge|divider|none"`, default `none`: with no handle there are no mouse zones, only keyboard resize.
  - On a normal pane in a split, `edge`/`divider` drag the border it shares with its next sibling (weight moves between the two, proportional to the weights they hold now); `corner` moves the nearest ancestor h-split edge horizontally and the nearest v-split edge vertically. All drags respect `min_*`/`max_*`.
  - Keys: `alt+r` enters resize mode (arrows ±1, shift+arrows ±5, Enter/Esc leaves); `alt+shift+r` resets the page (`tui.page.reset`, from 3D). Footer items show only when they apply (the footer already supports `KEY|LABEL|WHEN_FN`; add the focus and mode to its rebuild stamp).
  - Collapse: `default="expanded|collapsed"` (default `expanded`) is the first-build state and what a reset returns to; `collapsed="true"` is an alias (conflicting values are a validator error). `keep_collapsed="true"` keeps the state across page switches; it is parsed here and wired to the store in 3D. `collapse_to="title|0|rail"`: `rail` shrinks the pane to its buttons' `collapsed_text` (button attribute) along the parent's split axis, widgets without one are hidden.
- **Showcase page:** `share/demo/workspace.xml` (an on-call incident console: collapsible services rail, fused log viewer with draggable dividers, resizable command pane; 3B adds the detachable log and metrics windows) replaces `share/demo/styles.xml`. The Styles page (button classes, colour swatches) is dropped, not moved, and its nav entry goes in the same change that adds Workspace, so the nav never has a hole.

### 3B Layers: floating and detachable (roadmap F)
- **Uses:** 2A, 2B, 2C, 2D. **Owner:** `lib/chrome/tui_layer.sh` (new). **Seam:** `lib/chrome/tui_modal.sh` becomes a layer preset.
- **Tasks:**
  - Layer stack with z-order; anchors (`screen`/`parent`/`#id`); clamping to the screen.
  - `float`: move, resize, raise on focus, minimize, snap.
  - `detachable`: detach and dock are implemented as the `move` op, with a dock-target layer, `dock_group`, `leave=`, `on_detach`/`on_dock`, `persist="layout"`.
  - Overlay tags: `<window>`, `<modal>`, `<dialog>`, `<popup>`, `<tooltip>`, `<contextmenu>`, `<toast>`; zoom.
  - Focus scopes (trap and restore).
- **Agreed details:**
  - Floating windows get a header row: title left, two-column buttons right (reset position `↺`; fullscreen `⛶` only with `fullscreen="true"`; close/minimize use the same slots). Layers draw a drop shadow (one column right, one row below, glyph `▒`, class `.layer_shadow`; `shadow="false"` turns it off); the shadow counts in the damage rect.
  - `tui.page.refresh` leaves detached layers untouched; `tui.goto` closes non-persistent layers. Detach/dock work on the engine tree (not the node-store `move` op). `persist="layout"` is the last 3B task (needs the 3D store).
- **Deletes:** the overlay function registry and its full redraw after every render.
- **Done when:** the command palette and dialogs work unchanged on top of layers; golden frames cover overlapping layers; damage repaints only the rect a layer vacated.

### 3C Scrolling widgets (roadmap G)
- **Uses:** 2A, 2B, 2C. **Owner:** `lib/layout/tui_scroll.sh` (new).
- **Tasks:**
  - Content height taken from arranged children; offscreen virtualization.
  - `scroll_into_view` on focus, `tui.scroll.to`, `sticky="top"`, wheel routed to the innermost pane that can still scroll.
- **Deletes:** the output-only special cases in the scroll path.
- **Done when:** a form taller than its pane scrolls with Tab; the bench shows paint cost bounded by the viewport, not by content size.
- **Status:** done. Pinned rows use `pin="top"` instead of `sticky="top"` (`sticky` already names the input focus policy). Panes with `scroll="v"`, `"h"` or `"both"` hold widgets; content height comes from widgets, scroll offset follows wheel/keys (innermost widget first, then pane), a scrollbar is drawn in the right border column, Tab scrolls focused widgets into view (controlled by `scroll_into_view="true|false"`, default true). `tui.scroll.to TARGET [top|center|bottom]`; `pin="top"` (one pinned widget sticks at a time). Demo page `share/demo/scroll_form.xml`. The paint-cost bench is still to be run by hand.

### 3D Page state and shells (roadmap I)
- **Uses:** 2C, 2D. **Owner:** `lib/state/tui_store.sh` (new).
- **Tasks:**
  - One store keyed `page|id|field`.
  - `keep_focus`, `focus_on_enter`, `keep_value`, `keep_state`, `persist="session|disk"`.
  - `tui.page.reset`, `tui.page.reset_field`, `tui.page.reset_all`, exposed as actions and palette commands.
  - Shells: `shell=` + `<outlet/>`; shell nodes are never torn down.
  - From 3A: a `collapsed` field in the store (honours `keep_collapsed`, `keep_state` and `default` on reset), `alt+shift+r` bound to `tui.page.reset`, and the footer predicate "page has resettable state".
  - Disk format: a data-only file (one escaped `page TAB id TAB field TAB value` line per entry, read with `read`; nothing is sourced), so `TUI_HOME` is not a code-execution boundary.
- **Done when:** unit tests cover save and restore for each widget type; switching pages in a shell is faster than the full `tui.goto` baseline.

**Stage 3 gates:** G1–G8. `DABT_someApp` (separate repo) is migrated to shells, fused panes and nested widgets as the real-world check; its XML shrinks noticeably. This is the user's validation step at the end of the stage, not part of any feature task.

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
