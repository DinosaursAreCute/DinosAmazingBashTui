<div align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/logo-transparent.png" alt="D.A.B.T" width="560">

<h1><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/devex-update-1-87-5.svg" alt="DevEx Update 1.87,5" height="60"></h1>

<h3><em>Don't redo what you already know</em></h3>
</div>

1.75 removed the work the framework did for nothing. This update goes after the work that is left: **composing the same pane twice, forking for a timestamp, and rebuilding a page that has not changed.** Closing the command palette is **13 ms instead of 52**, switching pages by key is **106 ms instead of 229**, a terminal resize is **144 ms instead of 187**, and the demo's monitor, docs and settings pages no longer start a process on every visit, tick or keystroke.

<p align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/release/devex-1-87-5-improvements.svg" alt="Before and after: palette close -74%, switch by key -54%, resize -23%, and no forks in the demo callbacks" width="900">
</p>

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-result.svg" alt="The result" height="35"></h2>

Medians of probe-measured latency on a 150×45 terminal, deep profiler runs, 5 rounds: the run that closed 1.75 (`20260930-231054`) against the latest (`20261001-201315`).

| | 1.75 | 1.87,5 | |
|---|---|---|---|
| Command palette close | 52 ms | **13 ms** | −74% |
| Page switch by key (`alt+2`, components) | 229 ms | **106 ms** | −54% |
| Page switch, revisit | 196 ms | **156 ms** | −20% |
| Page switch, first visit | 190 ms | **184 ms** | −3% |
| Page switch, mean over all pages | 203 ms | **173 ms** | −15% |
| Terminal resize | 187 ms | **144 ms** | −23% |
| Theme switch, first use | 270 ms | **215 ms** | −20% |
| Hover, focus, click, scroll, warm and cold start, idle | | unchanged | within 3% |

Against the very first profiler run the page switch has fallen from 409 ms to 173 ms (mean) and the palette close from 143 ms to 13 ms.

Per page, revisit, 1.75 → 1.87,5: components 260 → 157 ms, monitor 274 → 186 ms, docs 244 → 214 ms, settings 197 → 146 ms, widgets 189 → 147 ms, scrolling 314 → 211 ms. The Terminal page's shell, which used to cost the next page 50 ms on the way out, is covered below.

<p align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/release/devex-1-87-5-pages.svg" alt="Page switch per page, 1.75 and 1.87,5" width="900">
</p>

**Still over budget:** revisit 156 ms (budget 100 ms) and first visit 184 ms (150 ms). A trivial page costs about 120 ms to revisit (cache replay 23 ms, render 28 ms, the rest probe and settle overhead); getting under 100 ms needs persistent shells rather than more tuning.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-what-changed.svg" alt="What changed" height="35"></h2>

- **Compose once, replay.** Panes, labels, buttons and checkboxes are composed once for each distinct input (geometry, state, text, style epoch) and replayed afterwards. The key holds every input, so a changed input is a different entry and a stale result cannot happen. A content-heavy page renders in 30 ms instead of 54 ms. Widget positions and coloured-line slices are memoised the same way.
- **Closing an overlay does not recompose the page.** `tui.render` keeps its frame; Esc or a click outside the palette flushes it again. Repaints that happen under the overlay (the header clock ticks every second) are folded into the saved frame, so it stays an exact copy of the screen. Anything else that invalidates it (a restyle, a resize, an erase) falls back to the full repaint.
- **No forks in demo callbacks.** The new `tui.capture VAR CMD ARGS...` is `VAR=$(CMD ARGS...)` without the subshell, and the demo uses it with builtins in place of `date`, `cat`, `awk`, `sed`, `nproc` and `df | tail | awk`. The monitor refresh went from about 20 forks to 1, the widgets and debug-lab ticks from 3 to 5 forks per run to none, and the components renderer view is built once per width.
- **The page cache is trusted once the app is up.** Pages, includes and themes are checked against the cache once, at start-up, and the files are assumed not to change while the app runs: a page switch no longer asks the file system anything (one `stat` call and about 3 ms less per switch). Edits made while the app is running take effect on the next start.
- **One menu width.** The menu is 18% wide on every page (it was 18, 20 or 22).
- **Coloured output is measured in bash.** `_tui._calc_bounds` no longer forks `awk` for output that carries colour. The result is identical to the old one on real renderer output and on 1,500 randomised lines.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-fixed.svg" alt="Fixed along the way" height="35"></h2>

- **Leaving the Terminal page.** A page that runs an interactive shell waited the full 50 ms for the shell to honour SIGTERM, which it ignores, and then killed it. The tree now gets a SIGHUP after the first poll: 55 ms became 11 ms, and the page visited next is 48 ms faster (the scrolling page, 211 → 163 ms).
- **A palette that never replayed.** The first version of the saved-frame replay invalidated itself on any paint under the overlay. The header clock repaints every second, so it fell back every time. Found by reading the call chain of the close in the profiler report.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-tools.svg" alt="New tools" height="35"></h2>

- **`tools/compare/`**: a DABT app and a Textual app with the same four pages (buttons, form, data, layout) and a black-box harness that drives both through a pseudo-terminal and prints latency, bytes, CPU and memory side by side. See its README for the caveats.
- **The profiler presses every page's key.** The `nav.key` scenario now runs `alt+2` … `alt+0, alt+1` instead of two keys, so the key-switch median covers all ten pages like the click scenarios do. Earlier `nav.key` numbers (including the 106 ms above, from components and case study only) are not comparable with it.
- **Release charts and headers as code.** `tools/release_charts.py` draws the charts of every release from one table; the block-font header generator (`tools/gen_header.sh`) now has a comma, which this release's title needs.
- **A developer guide for fast apps.** [Designing fast apps](https://dinosamazingbashtui.duckdns.org/guide/performance) covers budgets, the cost of a fork and of an array lookup, fork-free callbacks, memoising on inputs, and what defeats the caches.
- **The story and the data, updated.** [Making a pure-bash TUI feel instant](https://dinosamazingbashtui.duckdns.org/design/performance-journey) and the [Performance explorer](https://dinosamazingbashtui.duckdns.org/design/performance-explorer) include these runs.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-upgrade.svg" alt="Upgrade notes" height="35"></h2>

- **`tui.capture VAR CMD ARGS...`** is new. It runs `CMD` in the current shell and strips trailing newlines like `$( )`. Code that relied on `$( )` isolating a callee's globals must keep `$( )`.
- **Do not edit pages, includes or themes while the app is running.** Changes are picked up on the next start. If you develop a page with the app open, set `TUI_CACHE_TRUST=0` to keep the per-switch check.
- **`tui.modal.dismiss`** is new: close a modal without running anything (Esc, click outside). Keep `tui.modal.close` when a command runs after the close.
- **`TUI_ROWCACHE=0`** and **`TUI_DISMISS_REPLAY=0`** switch the two caches off, for checking whether one of them is behind a problem.
- **Widget text containing `${expr}`** is evaluated on every draw and bypasses the cache. Keep dynamic text in a variable and update it with `tui.update`.
- **Every `tui.style` call bumps a style epoch** that is part of every cache key. Restyling in a tick callback invalidates the cached widgets.
- **Page scripts are re-sourced on every visit.** `declare -gA memo=()` resets a memo each time; write `declare -gA memo` to keep it.
- **SIGHUP on page exit.** Processes started with `tui.exec` that survive the first 5 ms after SIGTERM now get a SIGHUP before the final SIGKILL.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-install.svg" alt="Install or update" height="35"></h2>

```bash
dabt update                     # existing install
curl -fsSL https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/install.sh | bash   # new install
```

The full list of changes is in the [changelog](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/CHANGELOG.md).
