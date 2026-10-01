# Making a pure-bash TUI feel instant

A terminal UI written in nothing but bash has no compiled fast path to fall back on: every frame, every hover and every page switch is shell code, and every external program it calls costs a process. This page is the short version of a performance project that profiled the real D.A.B.T demo app from the outside, found where the time was going, and cut it roughly in half across the board: **page switches from about 410 ms to 200 ms, startup from 6 s to 3 s, and the warm start from 860 ms to 290 ms**.

It is written for readers who want the result and the lessons. The interactive [performance explorer](performance-explorer.html) lets you compare any two profiler runs, and the [detailed log](../concepts/performance-progress.md) has every change with its expected and measured effect.

## At a glance

Medians of the profiler's probe-measured latency, first deep run against the latest deep run, on a 150×45 terminal.

| Interaction | Before | After | Change | Budget |
|---|---|---|---|---|
| Page switch, mean over all pages | 409 ms | 173 ms | **−58%** | — |
| Page switch, first visit | 356 ms | 184 ms | **−48%** | 150 ms |
| Page switch, revisit | 370 ms | 156 ms | **−58%** | 100 ms |
| Command palette close | 143 ms | 13 ms | **−91%** | 100 ms |
| Wheel scroll | 64 ms | 18 ms | **−72%** | 60 ms |
| Terminal resize | 260 ms | 144 ms | **−45%** | 250 ms |
| Idle repaints | 20.7 /s | 2.0 /s | **−90%** | 2 /s |
| Warm start | 857 ms | 294 ms | **−66%** | 1 s |
| Cold start (first launch) | 5.84 s | 2.86 s | **−51%** | 5 s |

Budgets are the "perceived instant" lines the profiler checks against. Everything except the page switches is now inside its budget; the page switches are the remaining gap, and they are dominated by a few heavy pages (see below).

```mermaid
xychart-beta
    title "Median latency (ms): before vs after"
    x-axis ["page first", "page revisit", "palette close", "wheel scroll"]
    y-axis "ms" 0 --> 400
    bar [356, 370, 143, 64]
    bar [184, 156, 13, 18]
```

*Pink: before. Blue: after.*

## The journey

Seventeen changes, each followed by a measurement. The page switch fell in steps; no single change did it.

```mermaid
xychart-beta
    title "Page switch (ms) after each change"
    x-axis ["base", "1-2", "3-4", "5", "6-7", "9", "10", "11", "12", "13", "14", "15-16", "latest"]
    y-axis "ms" 150 --> 420
    line [409, 377, 346, 308, 283, 251, 267, 239, 226, 203, 192, 200, 173]
    line [356, 320, 295, 260, 228, 201, 245, 208, 208, 190, 199, 204, 184]
    line [370, 339, 325, 264, 225, 216, 213, 216, 207, 196, 168, 168, 156]
```

*Pink: mean over all pages. Blue: first visit. Yellow: revisit. The bump at change 10 is the known first-visit run-to-run swing, not a regression. The first-visit points for changes 14 and 15-16 (199, 204 ms) are slightly above change 13: the fragment cache pays to build and store a key on a first visit and only wins on repeats.*

## Where the time went

The profiler runs the app twice: once untraced for honest latency, once with bash's `xtrace` to attribute time to functions and layers. For a page switch, the attributed time per layer looked like this:

```mermaid
pie showData
    title Page switch before: 343 ms
    "Subprocesses" : 79
    "Style" : 72
    "Flush" : 48
    "Layout" : 45
    "Render" : 33
    "Widgets" : 16
    "Other" : 50
```

```mermaid
pie showData
    title Page switch after: 157 ms
    "Subprocesses" : 20
    "Style" : 10
    "Flush" : 23
    "Layout" : 21
    "Render" : 21
    "Widgets" : 17
    "Other" : 45
```

Style and subprocess time almost vanished; what is left is the actual drawing work. That is where a further win would need a different approach (caching rows, not recomputing them). Changes 14 to 16 took that approach: panes and plain widgets are composed once per distinct input, and closing the palette replays the saved page. The measured effect is under "What we changed" and in the explorer.

## What we changed

| Theme | Change | Effect |
|---|---|---|
| **Fewer processes** | The pane renderer piped every coloured line through `awk`; it now slices in bash | Hover, click and scroll fork nothing; subprocess time per page switch halved |
| | One `stat` call for any number of files, and file reads without `cat` | Warm start 823 → 308 ms |
| | Page-build attribute reads, cache bookkeeping and path handling without `$(…)` | Cold start 5.5 → 2.9 s over two steps, 1,658 → 786 forks |
| | Killing a process tree on leaving the Terminal page slept 50 ms per process | 302 → 6 ms for a four-level tree |
| **Less waiting** | The main loop waited a full 50 ms poll before flushing a queued render | Scroll 58 → 18 ms; every page load about 40 ms |
| | The overlay redraw re-triggered itself every tick | Idle 20 → 2 frames a second |
| **Less repeated work** | Bordered panes rebuilt the same interior row for every row | About 20 ms off every full repaint |
| | Content fit scanned every widget once per pane, twice per render | Layout 42 → 26 ms per page switch |
| | Cached pages re-applied every widget's style on each visit | 25 ms per page switch |
| | On-visit code called `tui.render` a second time | Heaviest page: −90 ms |
| | Colour-code conversion recomputed per call | Memoised; style layer −85% together with the above |
| **Caching by content** | Panes, labels, buttons and checkboxes are composed once per distinct input (geometry, state, text, style epoch) and replayed; widget positions and coloured-line slices are memoised the same way | Render of a content-heavy page 54 → 30 ms; revisits −15% |
| | Closing the palette repainted the whole page from scratch | The saved page is replayed when nothing else painted: 38 → 14 ms |
| **Page code, not framework** | Demo callbacks forked on every visit, tick and keystroke (`date`, `cat`, `awk`, `$( )` around each renderer); a new `tui.capture VAR CMD` runs them in the current shell | Switch by key 201 → 106 ms; settings first visit 278 → 176 ms; monitor refresh 20 forks → 1 |
| | The same static renderer view was rebuilt on every visit | Built once per width |
| | Output widths of coloured lines forked `awk` | Measured in bash and memoised, identical results on 1,500 randomised lines |
| | A shell that ignores SIGTERM made leaving the Terminal page wait the full 50 ms | SIGHUP after the first poll: 55 → 11 ms; the next page's revisit 211 → 163 ms |
| **Found by profiling** | Key bindings from markup were lost on cached pages | `alt+1…0` navigation works on a warm start |

## Which pages gained most

The per-page view shows why the median barely moved after the later changes: the gains landed on the heaviest pages, which sit above the median.

```mermaid
xychart-beta
    title "Page switch revisit per page (ms): before vs after"
    x-axis ["componen.", "docs", "scrolling", "monitor", "settings", "widgets", "terminal", "layout", "case st.", "home"]
    y-axis "ms" 0 --> 650
    bar [618, 532, 488, 472, 372, 364, 358, 307, 283, 288]
    bar [157, 214, 211, 186, 146, 147, 153, 119, 109, 120]
```

*Pink: before. Blue: after.*

## Startup

A first launch has to validate every page and build the page cache; every later launch loads it. The cold start halved by removing forks from that build. The warm start dropped by two thirds once the cache check stopped spawning a `stat` process per file.

```mermaid
xychart-beta
    title "Startup (seconds) after each change"
    x-axis ["base", "1-2", "3-4", "6-7", "8", "12", "13", "14", "15-16", "latest"]
    y-axis "seconds" 0 --> 6.5
    line [5.84, 5.68, 5.61, 5.60, 5.54, 3.11, 2.87, 2.86, 2.86, 2.86]
    line [0.86, 0.86, 0.85, 0.82, 0.31, 0.30, 0.29, 0.29, 0.30, 0.29]
```

*Pink: cold start. Blue: warm start.*

## Lessons

- **Measure from the outside, then from the inside.** Probes inside the app give trustworthy latency; a bash trace gives attribution but runs about three times slower. Scaling the trace back to untraced speed per scenario kept the attribution within about 6% of the probes.
- **The biggest wins were not where the profile first pointed.** The 50 ms wait in the input loop and a duplicate render inside page code each cost more than any single hot function.
- **Forks are cheaper than assumed, but they still add up.** Removing 872 forks saved about 230 ms: roughly a quarter of a millisecond each, not the millisecond we had guessed.
- **A median hides the heavy pages.** Page-code changes moved the mean and the heaviest pages by up to 25% while the median stayed put. Look at both.
- **Some wins are correctness bugs.** The profiler's "this key does nothing" finding led to key bindings that had silently disappeared on every cached page.
- **Remove forks and waits before shaving arithmetic.** An associative-array lookup costs 2 to 3 µs in bash, so trimming a handful of lookups per widget moved a render by a few percent, while removing a fork or a wait moved a page by tens of milliseconds.
- **A wait that looks like another page's cost.** The scrolling page took 70 ms longer than the sum of its parts; the missing time was the Terminal page's interactive shell, which ignores SIGTERM, being waited out when you left it. Compare a page's total with its parts.
- **Cache on inputs, not on counters.** Row, geometry and slice caches are keyed on the values that produce them, so a stale result cannot happen. The first version of the palette replay invalidated itself on any paint under it and never ran, because the header clock repaints every second; folding those paints into the saved page fixed it.
- **Prove a rewrite is byte-identical.** Every fork-free conversion was compared with the old output (including a 1,500-line randomised comparison for the width measurement) before it was kept.
- **Keep the noise in view.** Run-to-run swings of up to 10% on first-visit medians and a bimodal resize timing meant that changes under about 3% were never reported as changes.

## How it was measured

The profiler drives the real demo in a hidden pseudo-terminal with a scripted user session (start, navigation, keys, mouse, scrolling, palette, themes, resize, idle, quit), five rounds for a deep run. Latency comes from probes around about twenty functions; attribution comes from a second, traced pass. It needs only bash 5 and Python 3: `tools/profiler/profile.sh`, with `--quick`, `--deep` and `--scenario` to choose what to measure.

## Explore the data

- [Performance explorer](performance-explorer.html): compare any two runs, follow one metric across every revision, see layers, hot functions and flame graphs.
- [Detailed log](../concepts/performance-progress.md): every change with its expected and real effect, plus the running comparison per revision.
