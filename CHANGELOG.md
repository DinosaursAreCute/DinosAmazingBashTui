# Changelog 📝

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.3] - 2026-09-14

### Added

* Mouse hover tracking: `tui.init` now enables xterm any-motion tracking (`\e[?1003h`), and widgets react live via `.class:hover` theme rules — see `docs/ui_markup.md` and the new architecture writeup, `docs/Bending-The-Planet-To-Your-Will_...md`.
* Pane borders react to `.class:focus` while any widget inside that pane has keyboard focus (`_tui._draw_pane_border`), reusing the same style mechanism instead of a second one for hover.
* Mouse-motion coalescing (`_tui._coalesce_mouse_motion`): a fast pointer sweep resolves and redraws hover state once, against the newest position, instead of once per crossed cell — droppable motion reports are distinguished from clicks/releases/wheel notches via the SGR protocol's own motion bit, and anything not dropped is rewound byte-for-byte (`_TUI_PENDING_INPUT`) so it's replayed in order.
* Configurable input timing knobs: `TUI_INPUT_POLL_TIMEOUT`, `TUI_INPUT_IDLE_TIMEOUT`, `TUI_ESCSEQ_BYTE_TIMEOUT`, `TUI_MOUSE_DRAIN_PEEK_TIMEOUT`, `TUI_MOUSE_DRAIN_MAX`.
* `split="grid"` pane layout: an R×C grid of cells sugar over `tui.hsplit`/`tui.vsplit`, with explicit (`grid_row`/`grid_col`) and loose (document-order) child placement, mixable on one grid; `rows`/`cols` may be omitted and are computed from item count; `fit="pack"`/`"stretch"` controls whether a short row leaves blank trailing cells or its cells expand to fill the row; `row_weights`/`col_weights` weight lists. Imperative form: `tui.grid`.
* `<checkbox>` widget — persistent boolean state, toggled by click or Enter, `action` called with the new value ("0"/"1"). `tui.checkbox`, `tui.checkbox.toggle`.
* `<tabs>`/`<tab>` container — a row of header buttons that swap a content pane, built on `split="grid"`; "active" reuses existing focus styling rather than a new style state. `style="compact"` (or `tui.tabs.compact`) switches to a borderless, background-color-indicated header for panes that can't spare the ~3 rows a bordered header needs. Imperative form: `tui.tabs.add`/`tui.tabs.build`/`tui.tabs.activate`.
* `tui.factory.*` — namespace-scoped dynamic construction/teardown (`label`/`button`/`input`/`checkbox`/`grid`/`clear`) for layouts whose shape isn't known until runtime, generalizing the `tui.exec` widget-group pattern beyond a hardcoded prefix.
* Automatic content-fit checking: a leaf pane's actual content (furthest widget row/longest widget text, or `tui.output`'s tracked line/width) is compared against its real size on every full render and resize, showing the existing `min space = …` warning without an explicit `min_width`/`min_height`. Scrollable panes are exempt; `strict_fit="false"` opts a specific pane out.
* `<tui on_visit="fn">` — a callback run once a page's panes/widgets are fully built (on every load, including a `tui.goto` revisit), for pages whose content isn't fully known from static markup (e.g. scanning a directory to build tabs).
* Opt-in render-time tracking: `_TUI_PERF_TRACKING=1` plus `tui.perf.mean_render_ms SECONDS`, timestamped via bash 5's `$EPOCHREALTIME` (fork-free) with a `date`-based fallback on older bash.
* `config/debug.xml` / `debug_callbacks.sh` — an observability page: a dynamically-sized interactive grid (rebuildable with a random item count), a capped input-event tape, live hover/focus status, and the render-time readout.
* `config/tabs_demo.xml` / `tabs_demo_callbacks.sh` — a fully declarative `<tabs>` usage example.
* `config/docu.xml` now discovers every `.md` file under `docs/` plus the README at load time (via `on_visit`) and builds one tab per file automatically, instead of a hand-maintained tab list.
* Checkboxes added to `settings.xml`'s forms demo (notifications, dark mode), read back in `on_theme_apply`.

### Changed

* `_tui._pane_at` no longer returns its result via `printf` captured through a subshell — it writes to a global (`_HIT_PANE`), matching the fork-free convention `_tui._hit_test` already used. `_tui._locate_pane` additionally short-circuits the full pane scan to 4 comparisons as long as the pointer stays inside the previously hovered pane.
* Consolidated five near-identical `mode.sync_start`/`printf`/`mode.sync_end` blocks into one `_tui._flush` helper (also the render-time tracking's single instrumentation point).
* `case_study.xml` and `docu.xml` migrated from hand-rolled tab-button wiring to `<tabs style="compact">` — neither page's header pane has the ~3 rows a framed header cell needs; `tabs_demo.xml`'s header pane was given more weight instead, to keep it a working example of the default framed style.
* `tui.tabs.activate` now passes the tab id to its `action` callback (backward compatible — existing zero-arg callbacks simply ignore it).
* `tui.tabs.build` now exempts every header cell it creates from the content-fit checker (`strict_fit="false"`) — a tab label clipping when there isn't room is expected UI behavior, the same as a nav sidebar button, not a real "this pane is broken" condition worth a warning.

### Fixed

* **`tui.render` was losing the content-fit cache it had just computed.** `_tui._refresh_content_fit`'s writes happened inside `tui.render`'s `buf="$( … )"` command substitution — a subshell — so `_TUI_P_EFFECTIVE_MINW`/`_MINH` never actually reached the running shell; every later hover/focus/click-triggered redraw (which runs outside that subshell) read an empty cache and silently treated it as "no minimum." In practice this showed as a pane's size warning and widget text flip-flopping depending on which code path happened to touch it last (visible on `<tabs>` header cells: the label was blank until hovered, a border appeared on click, and it went blank again the moment a different tab was clicked). Fixed by computing the cache for every leaf pane in the parent shell before entering the subshell.
* Scrollbar jump-to-click no longer fires on bare hover motion (`btn` values without a button actually held) — previously any-motion tracking made hovering a scrollbar track snap the viewport as if it had been clicked.
* `tui.factory.*` constructors no longer `printf` the id they generate — in a TUI, stdout is the screen, and calling one in a loop without capturing it (an easy mistake, not just a hypothetical) wrote raw id text straight onto the terminal outside any pane. The id is still available via `_TUI_FACTORY_LAST_ID`.
* Render-time tracking (`_tui._now_us`) no longer crashes under a locale where `$EPOCHREALTIME`'s decimal separator isn't `.` (e.g. `de_DE.UTF-8` uses `,`) — splits on the first/last non-digit character instead of a literal period.
* Fixed `tui.focus`/`_tui._unfocus` throwing `bad array subscript` the first time focus moved and there was no previously-focused widget (bash treats an empty-string subscript on an associative array as invalid, not merely absent) — added `_tui._widget_pane`, which returns empty for an empty id instead of indexing.
* `case_study.xml`'s "Technical Document" tab pointed at a doc path that no longer existed after a file rename; corrected, and made path-resolution independent of the current working directory (`${SCRIPT_DIR}` instead of a relative `../docs`).
* `home.xml`: the footer pane's `border="heavy"` needed 3 rows it never had (weight gave it ~2), and one feature-list label didn't fit the page's own content pane at 80-column terminals — both silently clipped before the content-fit checker existed to report it, now fixed.
* `_nav.xml`: the "Documentation" label didn't fit the nav sidebar at 80 columns, shortened to "Docs".

## [0.0.2] - 2026-09-13

### Added

* High-performance scrolling viewports enabled via the `scroll="v"`, `scroll="h"`, or `scroll="both"` pane attributes.
* Single-pass AWK "Shader" architecture for rendering: handles ANSI-safe horizontal slicing, padding, and absolute cursor positioning in a single compiled execution block to bypass Bash subshell bottlenecks.
* "Jump-to-Click" scrollbars: clicking horizontal or vertical pane borders instantly calculates relative percentages and snaps the viewport offset.
* Mouse wheel support for vertical scrolling (buttons 64/65).
* Shift + Mouse wheel support for horizontal scrolling (buttons 68/69).
* Keyboard scrolling navigation utilizing Vim bindings (`hjkl`) and Shift+Arrow keys (intelligently gated so they type normally when focusing a text input field).
* Render debouncing / batching system (`_TUI_PENDING_RENDER` and `_TUI_RENDER_TIMEOUT`) to prevent UI lag during rapid input events like continuous mouse-wheel spins.
* Lazy pre-computation caching (`_TUI_P_LINES` and `_TUI_P_MAX_W`) that evaluates string dimensions instantly upon injection to speed up scroll math.
* `tui.output`, `tui.output_append`, `tui.output_clear` — render arbitrary multi-line content into a pane with ANSI color passthrough, auto-scroll, and visible-width truncation, without requiring `tui.exec` or a PTY.
* Shared ANSI-aware text helpers: `_tui._clean_ansi` (strip control sequences, preserve SGR colors) and `_tui._visible_truncate` (truncate to N visible characters without breaking escape sequences).
* Pane output content survives `tui.render` / resize — stored in `_TUI_PANE_CONTENT` and re-rendered automatically.
* Renderer showcase page (`components.xml`, `showcase_callbacks.sh`) demonstrating all twelve `terminal_renderer.sh` commands via `tui.output`.
* `scrolling.xml` demo page to showcase independent vertical, horizontal, and multi-axis scrolling capabilities.
* `case_study.xml` page providing a real-world layout stress test, rendering a live Markdown document alongside a complex system metrics table.
* `show_all` callback composing every renderer into a single scrollable output.
* `.sc_purple` theme class.

### Changed

* Completely rewrote `_tui._render_output` to eliminate slow Bash subshell `for` loops, replacing them with a highly optimized `awk` backend.
* Redesigned the `tui.run` main event loop to intercept scroll actions and defer rendering until the input stream pauses.
* `_exec_render_output` now bypasses the widget system entirely, routing the execution buffer directly through the new AWK shader for correct ANSI passthrough and high FPS.
* `_exec_tick` updated to enforce a 2500-line rolling ring-buffer cap on `_EXEC_BUF` to prevent memory blowouts during infinite streaming processes.
* `_exec_strip_ansi` replaced by `_exec_clean_line` — preserves SGR color/style sequences instead of stripping all ANSI codes.
* `_exec_setup_output_pane` no longer creates per-row `_xo_N` label widgets.
* `_exec_tick` keeps blank lines in the output buffer to preserve intentional newline spacing.
* Line truncation in exec output uses `_tui._visible_truncate` instead of byte-position `${text:0:N}`, which could split escape sequences mid-byte.
* Re-mapped UI hit testing in `_tui._handle_mouse` to support dynamic hover tracking (`_TUI_HOVERED_PANE`) to know where to route scroll wheel events.

### Fixed

* Fixed a severe formatting break and vertical scroll-locking bug by forcing `tui.output` to split multiline strings via `mapfile` instead of injecting massive blocks into index `0`.
* Fixed a scope-loss crash (`arithmetic syntax error`) when sourcing the renderer script by assigning the `_BANNER_FONT` associative array to global scope (`declare -gA`).
* Fixed a typo inside `_tui._layout` where `$pc0` was incorrectly evaluated instead of `$pc`, displacing vertically split panes to the left screen edge.
* Fixed recursive layout bug in `_tui._layout` where the `for` loop variable `i` was not declared `local`, causing child calls to clobber the parent's loop counter and skip all sibling panes after the first container child in a nested split.

### Deprecated

* `_exec_strip_ansi` — replaced by `_tui._clean_ansi` / `_exec_clean_line`.

### Removed

* Removed inefficient continuous mouse dragging logic (and `wc -l` subshell checks) from `_tui._handle_mouse` in favor of Jump-to-Click tracking.
* Removed arbitrary math multipliers for scroll speeds, syncing offsets exactly to pre-computed text length ratios.

### Security

* (No relevant security changes in this release)