# Cheap Redraws

Status: Concept. This document surveys rendering optimization strategies employed by other terminal UI frameworks and proposes a prioritized approach for implementation.

## 1. Performance Baseline

Profiling data from `tools/profiler` on a 150x45 terminal with the demo application:

| action | frames | bytes written | time |
|---|---|---|---|
| hover, focus move | 0-2 | 0-0.5 KB | 3-10 ms |
| page switch | 7-10 | 40-100 KB | ~360 ms |
| command palette close | 3 | 58 KB | 143 ms |
| resize | 3 | 36 KB | 260 ms |
| idle | 21 frames/s | 10 KB/s | 2.8% of a core |

Incremental drawing is already effective for low-impact interactions such as hover and focus changes. Expensive operations that trigger full repaints are page transitions, overlay dismissal, and terminal resize events. Analysis indicates that computational cost dominates terminal bandwidth, with style composition, output flushing, layout calculation, and rendering accounting for approximately 70% of page switch latency.

## 2. Architectural Constraints

Terminal UI frameworks written in compiled languages employ cell-level diffing across grid states to minimize redraws. Bash's runtime characteristics present a fundamentally different optimization surface: per-cell iteration costs tens of microseconds, making a 150x45 grid (6,750 cells) prohibitively expensive as a diffing granularity. Conversely, Bash excels at string operations, which execute at C speed, and string emission via `printf` is effectively free.

This constraint establishes the operational level: row and region granularity rather than cell granularity, with pre-composed strings as the unit of work rather than cell objects.

## 3. Optimization Strategies

### A. Per-Pane Row Cache with Memoization

Cache the finished output rows (text pre-joined with escape sequences) in a per-pane array, indexed by the inputs that produced them: content version, pane dimensions, style epoch, and interaction state (focus/hover). When a pane's inputs remain unchanged, the cached rows are emitted directly; recomposition occurs only when the input set changes.

Precedent: React's memoization and keyed reconciliation, Flutter's repaint boundaries, Qt's backing store, and Textual's per-widget line cache with region-level invalidation all employ this pattern.

Assessment: High potential. Reduces composition to a version-counter comparison, a low-cost operation in Bash.

### B. Persistent Chrome Layer

Header, navigation, and footer elements remain unchanged across page transitions, yet current behavior repaints the entire screen. Separate these fixed elements into a dedicated layer with independent caching, updating only the content region upon page change.

Precedent: Web browsers and game engines partition scenes into layers with selective repainting; windowing systems employ per-window backing stores. ncurses panels use `update_panels` to compute visible regions and refresh only those.

Assessment: High potential. Likely represents the most significant single optimization opportunity for navigation, as 40-100 KB of current page-switch output replicates unchanging chrome.

### C. Overlay State Preservation

Closing a palette or modal dialog currently triggers a full screen layout and repaint (58 KB). When an overlay opens, the rows beneath its bounding rectangle are available from the per-pane caches (Strategy A). Overlay dismissal can then repaint only the affected row slices instead of the entire screen.

Precedent: Legacy graphical interfaces employed "save bits" beneath popup menus; X11 backing stores; ncurses `overlay`, `copywin`, and panel library show/hide operations.

Assessment: High potential, contingent on Strategy A implementation. Without per-pane caches, the saved region would require capture from the terminal's visible buffer, which cannot be retrieved.

### D. Line-Level Diffing

After frame composition, compare each output row against its predecessor via string comparison and emit only rows with changed content. This approach is O(rows) with string comparison at native speed.

Precedent: Bubble Tea's default renderer implements line-by-line comparison with selective emission and frame-rate limiting. Blessed performs line-level diffing against the prior screen state. ncurses maintains `curscr` and `newscr` and uses `doupdate()` to transmit differences; Ratatui and tcell apply per-cell diffing, an approach infeasible in Bash.

Assessment: Medium potential. Serves as a fallback optimization behind Strategies A-C but requires full-frame composition first, reducing savings to byte transmission rather than composition cost.

### E. Terminal-Native Scroll Operations

Current scrolling behavior rewrites all visible rows. Terminals support native content shifting: define a scroll region via escape sequences (`CSI t;b r`), then shift content using `CSI n S` / `CSI n T` (or insert/delete line operations), emitting only the newly visible rows.

Precedent: ncurses implements this via `idlok` and `scrollok`; Vim and notcurses employ the same approach.

Assessment: High potential for scrollable pages (60-70 ms per wheel tick, 4 KB per frame). Implementation is orthogonal to Strategies A-D.

### F. Output Byte Minimization

Several low-cost techniques reduce output size once frame content is determined:

- Replace run-of-spaces with erase-to-end-of-line escape sequences (`CSI K`) and character repetition (`CSI n b`).
- Emit escape sequences only upon attribute changes, skipping redundant emissions (ncurses implements this by tracking current terminal state). Precomputed transition strings enable constant-time lookups.
- Select cursor movement encoding (relative vs absolute positioning) based on byte cost (ncurses `mvcur` implements this heuristic).

The style caching strategy described in `sgr-cache-plan.md` is a prerequisite for the transition-string optimization.

Assessment: Medium potential with low implementation risk. Combines favorably with all prior strategies.

### G. Static Page Pre-rendering

Pages exhibit significant static content. Pre-render complete frames (or static row subsets) for target terminal sizes during the cache-initialization phase, and emit pre-rendered output on navigation, applying dynamic widget patches afterward. The existing page cache maintains the widget tree; this strategy extends it to cache the final rendered output, indexed by size and style epoch.

Precedent: Static site generation and partial pre-rendering in web development; baked lighting computation in game engines.

Assessment: High payoff, highest complexity and storage overhead. Natural successor to Strategy A, as the per-pane row cache is the mechanism being pre-built.

### H. Dirty-Region Batching

Widget state changes mark affected regions dirty and return immediately; a single redraw phase per input tick composes and flushes the union of dirty regions (analogous to Qt's `update()` with batched `paintEvent`, or Elm/React's automatic batching). This approach also eliminates unnecessary idle repaints: no dirty regions means no rendering. Current behavior shows overlay redraws re-triggering every main-loop iteration at 21 frames/s; dirty-region batching prevents this by design.

Assessment: High potential, and resolves idle performance as an inherent consequence of the design.

## 4. Implementation Sequence

1. **H** (Dirty-Region Batching): Establish batched rendering per input tick, measure frame count and byte throughput per action.
2. **A** (Per-Pane Row Cache): Implement version-keyed per-pane row caching.
3. **B** (Persistent Chrome Layer) and **C** (Overlay Preservation): Both depend on Strategy A; implement in sequence.
4. **E** (Terminal Scroll Operations): Independent implementation, can proceed in parallel with other work.
5. **D** (Line-Level Diffing) and **F** (Output Byte Minimization): Byte-level optimizations, apply after core strategies.
6. **G** (Static Page Pre-rendering): Implement only if page switch latency remains above target thresholds.

## 5. Acceptance Criteria and Testing

Performance targets per action are established as follows: page switch latency under 100 ms with 1-2 frame renders; palette dismissal under 30 ms with output under 10 KB; terminal resize under 120 ms; idle operation below 2 frames/s and 0.5% core utilization. Hover and focus-change performance must not regress relative to baseline. Tests remain host-independent: byte-stream output is validated against golden frames for each page and theme combination.

## 6. Open Questions

- Memory footprint of the row cache for the largest pages at multiple sizes. An LRU eviction strategy should establish bounds.
- Identification of widgets with per-frame state changes (clocks, monitors, charts). These require exclusion from pane-level caching or assignment of dedicated dirty regions.
- Terminal support coverage for scroll regions and synchronized output across all DABT deployment environments. Both have fallback behavior (full repaint).
- Ownership model for cache invalidation when application callbacks directly mutate widget state. All mutation paths must touch the applicable version counter, following the discipline of the style epoch mechanism.

## 7. Implementation status

Content-addressed fragment cache (`lib/render/tui_rowcache.sh`, strategy A at pane and widget granularity). A fragment is keyed on geometry, state, resolved content and `_TUI_RC_EPOCH` (bumped by `tui.style` and the page style reset), so a changed input is a different key and nothing is registered per widget. Texts containing `${expr}` bypass the cache. Wired into `_tui._draw_pane_buf` (bordered panes) and `_tui._draw_widget_buf` (label, button, checkbox). Kill switch: `TUI_ROWCACHE=0`. Counters: `rowcache_hit`, `rowcache_miss`.

Not done: emission-level diffing. The 2026-09-30 40-switch bench shows flush at 0.29 ms mean against render at 48 ms, so skipping bytes saves nothing measurable, and skipping a fragment on screen is unsafe while panes redraw over their children. Revisit after the before/after bench.

Measured 2026-10-01, `tools/bench/page_switch.sh 40` (150x45 demo, same machine, cache off vs on):

| | off | on |
|---|---|---|
| render span mean | 50.6 ms | 36.7 ms |
| render span p95 | 78.4 ms | 89.0 ms |
| warm page switch (home / components / widgets) | 39 / 83 / 46 ms | 24 / 46 / 32 ms |
| wall per switch (incl. 6 cold loads) | 177 ms | 164 ms |
| fragments replayed / composed | 0 / 1702 | 1354 / 348 |

Hit rate 80%. Each cold first visit pays the miss cost once; its p95 is noise from the 6 cold loads.

### Overlay dismissal (strategy C, implemented as base-frame replay)

`tui.render` saves its frame (`_TUI_BASE_FRAME`). `tui.modal.dismiss` (esc, click outside the palette) replays it instead of re-composing the page, but only while the screen still matches: every flush after the base must be an overlay draw (`_TUI_FLUSH_GEN - _TUI_BASE_GEN == _TUI_OVL_FLUSHES`), the style epoch and terminal size are unchanged, and nothing called `erase.all` or painted outside `_tui._flush`. Otherwise it falls back to `tui.modal.close` (full relayout). Closes that run a command (enter) still use the full path, since the command may change state the saved frame does not know about. Switch: `TUI_DISMISS_REPLAY=0`. Counters: `dismiss_replay`, `dismiss_full`, span `dismiss`.

Row-level replay was rejected: some draw paths set a style once and then write several rows (`_tui._fill_pane_bg`), so a single row cut out of the frame can come out in the wrong colours. Consequence: output bytes on dismissal stay at the full-frame size (about 37 KB); the saving is composition time, not bytes.
