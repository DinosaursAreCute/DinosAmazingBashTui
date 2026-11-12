# Debugging an app: debug mode and the dev tools

`dabt --debug` turns on a status strip and a dev-tools dock inside the running app. They show what the framework is doing (page cache, page loads, frame times, input latency) without leaving the terminal and without slowing a normal run.

## 1. Starting it

```bash
dabt --debug                 # every event category
dabt --debug=cache,render    # only these categories
```

`--debug` sets `TUI_DEBUG=1` (and `TUI_DEBUG_CATS` for a category list). An app started another way can set the same variables, or call `tui.debug.enable [CATEGORIES]`. Without debug mode the hot paths pay one arithmetic test and no function call.

| key | does |
|---|---|
| F12 | shows or hides the status strip |
| F11 | opens the dev-tools dock; focuses it when it is open; closes it when it has focus |

Both are also in the command palette.

## 2. The status strip

One row above the footer, written only when its text changes. Its row is taken from the page, so it never covers content.

| segment | shows |
|---|---|
| `pages` | cached pages out of known pages |
| `build` | the cache pool building or re-fitting pages |
| `visit` | the last page load: page, hit or miss, ms |
| `ready` | first visits that found their page already cached |
| `switch` | the whole last `tui.goto` in ms |
| `input` | the last key or click until its frame is flushed |
| `render` | frame write time in ms |
| `cache` | row-cache hit rate |
| `miss` | cache misses |
| `boot` | disk and stale pages at start (off by default) |
| `hint` | the F11 hint (right side) |
| `last` | the newest event (right side) |

Left segments that do not fit are dropped from the end. `tui.debug.segment.toggle ID` switches one on or off.

### Your own segment

```bash
_seg_jobs() { _DBG_SEG="jobs ${#_MY_JOBS[@]}"; }   # empty text hides the segment
tui.debug.segment jobs _seg_jobs left
```

The function runs on every strip repaint: no forks.

## 3. The dev-tools dock

`F11` opens a dock above the strip; the app stays visible above it. It takes about 30% of the terminal, at least 8 rows. A 4 Hz tick keeps it live while the app is idle.

| tab | content |
|---|---|
| Events | live event log with times relative to the start of the run |
| Pages | the page cache and the page loads |
| Perf | span timings |
| Counters | perf counters and event totals |

While the dock has focus, these keys are its own; every other key still reaches the app. They are unbound again on blur.

| key | does |
|---|---|
| `←` `→` or `1`-`4` | switch tab |
| `↑` `↓` `pgup` `pgdn` | scroll (Events: back in time) |
| `home` `end` | top, follow the newest |
| `p` | pause or resume the Events tab |
| `f` | cycle the Events category filter |
| `c` | clear events |
| `m` | maximise or restore the dock |
| `esc` | give the keyboard back to the app; the dock stays open |

## 4. Recording your own events

```bash
((TUI_DEBUG)) && tui.debug.event cache.page.miss "$page"
```

`NAME` is `CATEGORY.what`; the text before the first dot is the category, and `--debug=CATS` keeps only those. Events are counted and kept in a ring buffer of the newest `TUI_DEBUG_RING_MAX` (default 500). Guard the call with `((TUI_DEBUG))` in hot code so a normal run skips the function call. `tui.debug.reset` clears the buffer and the counters.

Events the framework records: `page.visit`, `page.switch`, `input.done`, `cache.page.miss`.

## 5. Theme classes

The strip and the dock use theme classes and fall back to built-in colours when a theme has none.

| class | styles |
|---|---|
| `.debugbar`, `.debugbar_chip`, `.debugbar_warn` | the strip, its DEBUG chip, cache misses |
| `.devtools`, `.devtools_head` | the dock body and header |
| `.devtools_tab`, `.devtools_tab_active` | the tabs |
| `.devtools_warn`, `.devtools_dim` | warnings, secondary text |

## 6. Reference

[`tui.debug.bar`](../api/core/tui.debug.bar.md), [`tui.debug.devtools`](../api/core/tui.debug.devtools.md), [`tui.debug.segment`](../api/core/tui.debug.segment.md), [`tui.debug.segment.toggle`](../api/core/tui.debug.segment.toggle.md), [`tui.debug.event`](../api/core/tui.debug.event.md), [`tui.debug.enable`](../api/core/tui.debug.enable.md), [`tui.debug.reset`](../api/core/tui.debug.reset.md), [`tui.debug.init`](../api/core/tui.debug.init.md). To measure a change rather than watch it, see [Designing fast apps](performance.md).
