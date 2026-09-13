# Changelog 📝

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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