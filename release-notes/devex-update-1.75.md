
<div align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/logo-transparent.png" alt="D.A.B.T" width="560">

<h1><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/devex-update-1-75.svg" alt="DevEx Update 1.75" height="60"></h1>

<h3><em>Blowing up the mountain because climbing is hard</em></h3>
</div>

We profiled the real app from the outside, found where the time was going, and stopped climbing. **Page switches are twice as fast, a launch with a warm cache takes 1.29 s instead of 0.86 s, the very first launch takes 2.9 s instead of 5.8 s, and an idle app no longer repaints 20 times a second.** How you write apps does not change, apart from the short upgrade notes at the end.

<p align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/release/devex-1-75-improvements.svg" alt="Before and after: idle repaints -90%, wheel scroll -73%, warm start -66%, palette close -64%, cold start -50%, page switch -50%" width="900">
</p>

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-result.svg" alt="The result" height="35"></h2>

Medians of probe-measured latency on a 150×45 terminal, first profiler run against the latest.

| | Before | After | |
|---|---|---|---|
| Page switch, mean over all pages | 409 ms | **203 ms** | −50% |
| Page switch, first visit | 356 ms | **190 ms** | −47% |
| Page switch, revisit | 370 ms | **196 ms** | −47% |
| Command palette close | 143 ms | **52 ms** | −64% |
| Wheel scroll | 64 ms | **17 ms** | −73% |
| Mouse hover | 9.4 ms | **8.1 ms** | −14% |
| Mouse click | 11.4 ms | **10.0 ms** | −12% |
| Idle repaints | 20.7 / s | **2.0 / s** | −90% |
| Warm start | 857 ms | **287 ms** | −66% |
| First launch (cold start) | 5.84 s | **2.90 s** | −50% |

The heavy pages gained most. The components page went from 618 ms to 260 ms, docs from 532 ms to 244 ms.

<p align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/release/devex-1-75-pages.svg" alt="Page switch per page, before and after" width="900">
</p>

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-mountain.svg" alt="What blew up the mountain" height="35"></h2>

Thirteen changes, each measured on its own. No single one did it; the profiler showed us where the next one was.

- **Fewer processes.** Hover, focus and scroll no longer start a single process (a hover used to spend 3 ms starting them), and a click spends 1.7 ms instead of 12 ms: the pane renderer used to pipe every coloured line through `awk`. The page cache checks every file with one `stat` call instead of one per file, and building a page no longer forks for every attribute it reads. A first launch went from over 12,000 forks to about 790, and a warm start starts 119 fewer `stat` processes.
- **Less waiting.** The main loop waited a full 50 ms before flushing a queued render. It now waits 10 ms, which took a scroll step from 58 ms to 18 ms and about 40 ms off every page load.
- **Less repeated work.** Panes drew the same interior row once per row, layout scanned every widget once per pane, cached pages re-styled every widget on every visit, and some pages rendered twice. Each is now done once.
- **Smarter caches.** Colour-code conversion is memoised, cached pages skip re-applying styles when the theme has not changed, and start-up validation reads every file's timestamp in one call.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-fixed.svg" alt="Fixed along the way" height="35"></h2>

- **Key bindings on cached pages.** `<bind>` tags (`alt+1`…`alt+0`, `alt+n` and every page binding) were lost on every page restored from the cache, which is every warm start. The profiler flagged "this key does nothing"; bindings now survive a replay.
- **Idle repaint loop.** Overlays such as the footer redrew on every tick, forever, because their own redraw triggered the next one. An idle app now repaints about twice a second (the clock) instead of twenty times.
- **Leaving a page with a live process.** Leaving a page that runs a `tui.exec` process slept 50 ms for every process in its tree and scanned `/proc` for each level: 302 ms for a four-level tree, now 6 ms.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-tools.svg" alt="New tools" height="35"></h2>

- **The profiler.** `tools/profiler/profile.sh` drives the real app in a pseudo-terminal with a scripted user session, measures latency with in-app probes and attributes time to layers and functions from a bash trace. It prints a terminal report, writes an HTML report with a flame graph and compares itself with the previous run. `--quick`, `--deep` and `--scenario` choose what to measure. It needs only bash 5 and Python 3.
- **The story, and the data.** [Making a pure-bash TUI feel instant](https://dinosamazingbashtui.duckdns.org/design/performance-journey) tells the project in ten minutes. The [Performance explorer](https://dinosamazingbashtui.duckdns.org/design/performance-explorer) lets you compare any two profiler runs, follow one metric across every change and open the flame graphs. The [detailed log](https://dinosamazingbashtui.duckdns.org/concepts/performance-progress) has every change with its expected and real effect.
- **Charts in the brand colours.** Diagrams on the documentation site now follow the DABT palette and the light/dark toggle.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-upgrade.svg" alt="Upgrade notes" height="35"></h2>

- **`TUI_INPUT_SETTLE_TIMEOUT`** (default `0.01` s) is new: how long the input must stay quiet before a queued render is flushed. If a slow mouse-wheel spin feels choppy because notches more than 10 ms apart now flush one by one, raise it (`0.02` is a good next step).
- **`tui.render` inside `on_visit`.** `tui.goto` now renders once after a page has loaded and skips `tui.render` calls made while it loads. Code in `on_visit` that calls `tui.render` needs no change, because the page is drawn right after it. Incremental calls such as `tui.update` and `tui.output` are not affected. Only code that depended on a full repaint in the middle of `on_visit` would notice.
- **Old page caches.** Cached pages written by an earlier version do not contain their key bindings until they are rebuilt. A cache is rebuilt when one of its page files changes. If `alt+1`…`alt+0` do nothing after updating, remove `$TUI_HOME/cache/pages/` and start once.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-install.svg" alt="Install or update" height="35"></h2>

```bash
dabt update                     # existing install
curl -fsSL https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/install.sh | bash   # new install
```

The full list of changes is in the [changelog](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/CHANGELOG.md).
