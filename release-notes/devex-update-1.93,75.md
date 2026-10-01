<div align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/logo-transparent.png" alt="D.A.B.T" width="560">

<h1><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/devex-update-1-93-75.svg" alt="DevEx Update 1.93,75" height="60"></h1>

<h3><em>Grinding the cleanup rubble to dust</em></h3>
</div>

1.87,5 took the forks out of the callbacks. This update goes after what was left in a page switch: a cache that never hit across pages, a snapshot rewritten line by line on every replay, a footer rewritten on every render and a relayout nobody needed. **A switch between trivial pages is 86 ms instead of 136, a page revisit 125 ms instead of 152,** and the profiler can now show where every millisecond of a switch goes.

<p align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/release/devex-1-93-75-improvements.svg" alt="Before and after: trivial-page switch -37%, page revisit -18%, first visit -21%, no stty process per page switch" width="900">
</p>

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-result.svg" alt="The result" height="35"></h2>

Medians of probe-measured latency on a 150×45 terminal.

| | 1.87,5 (v0.0.21) | 1.93,75 | |
|---|---|---|---|
| Page switch between trivial pages (floor scenario) | 136 ms | **86 ms** | −37% |
| Page switch, revisit | 152 ms | **125 ms** | −18% |
| Page switch, mean over all pages | 165 ms | **137 ms** | −17% |
| Page switch, first visit | 180 ms | **143 ms** | −21% |
| Page switch by key, all ten pages | 124 ms | **101 ms** | −19% |
| Hover, focus, click, scroll, palette close, warm and cold start, idle | | unchanged | within 3% |

How these were measured, so you can judge them: the floor figures are probe spans of the new `--scenario floor` (run `20261001-211251` on the code of v0.0.21, then the deep run `20261001-230749`). The other rows compare a navigation run of the v0.0.21 build (`20261001-204153`, 10 rounds) with the same interactions in the deep run `20261001-230749` (full scenario, 5 rounds, idle machine). Three lines need a word. The terminal resize median swings between 145 and 203 ms from run to run because its three timing targets swap between two modes; it did not change. The first theme switch (230 ms) sits inside the 215 to 242 ms it has had since 1.75. The palette close is 14 ms, but a clock tick that lands inside the profiler's settle window makes some samples read 78 ms; the first frame is on screen after about 3 ms of work.

Per page, revisit, v0.0.21 → 1.93,75: home 117 → 91 ms, case study 105 → 86, layout 114 → 94, components 153 → 125, widgets 148 → 124, settings 141 → 121, terminal 145 → 129, scrolling 162 → 143, monitor 179 → 161, docs 214 → 188. The first visit is inside its 150 ms budget (143 ms); the revisit (125 ms, budget 100 ms) is not yet.

<p align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/release/devex-1-93-75-pages.svg" alt="Page revisit per page, 1.87,5 and 1.93,75" width="900">
</p>

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-what-changed.svg" alt="What changed" height="35"></h2>

- **The fragment cache now hits across pages.** Its key held a counter that every page switch bumped, so a fragment composed on one page was never reused on the next: 57 stores per switch and no savings. The key now holds the style strings a pane or widget draws with, so the menu and header (identical on every page since the menu width was aligned) are composed once. The render of a trivial page went from 58 to 28 ms.
- **The page snapshot is rewritten once.** Every replay used to rewrite each `declare` line of the snapshot in a bash loop (7 of a 9.5 ms restore); the rewrite now happens when the page is recorded. Snapshots from earlier versions still restore.
- **No process, no write, no rebuild without a reason.** A running app no longer forks `stty size` on every page switch. The footer writes its row only when its content, the size or the screen changes, and an overlay pass that draws nothing writes and flushes nothing. The key-hint map is rebuilt only when the bindings change. A replay at the size the page was recorded at skips the relayout.
- **A leaner widget draw.** One pane lookup per widget and the clip reuses the inset the position step just computed.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-fixed.svg" alt="Fixed along the way" height="35"></h2>

- **A test race that could fail a release.** The demo's header script forced the log directory to the current directory, so running a demo page (as `layout.bats` does) wrote a log file into the repository root, and the "never touches the source tree" tests failed intermittently when they ran in parallel with it. The demo now logs to its config folder like every app.
- **A golden-frame check that checked nothing.** `tools/frame.sh` set the terminal size before sourcing the library, which resets it to 0 on load, so every page was laid out in a 0×-1 area and rendered as one line. The size is now set after the source, the golden frames are byte-exact streams (cursor moves and colours included, clock times blanked), `tools/gate.sh` runs them as gate G4, and the new caches were verified byte-identical with the cache on and off.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-tools.svg" alt="New tools" height="35"></h2>

- **The page-switch floor in the profiler.** `tools/profiler/profile.sh --scenario floor` replays warm switches between the three lightest pages. The report's new "Page-switch floor" section (terminal deep dive and `report.html`) breaks `tui.goto`, `tui.cache.replay`, `tui.render` and their neighbours down without pruning: which callee each millisecond went into, which function ran the commands and the hottest source lines.
- **A byte-exact golden check in the gate.** `tools/gate.sh G4` compares the rendered byte stream of every stable demo page.
- **Charts and the explorer.** `tools/release_charts.py` draws the charts of this release; the [Performance explorer](https://dinosamazingbashtui.duckdns.org/design/performance-explorer) and [the performance journey](https://dinosamazingbashtui.duckdns.org/design/performance-journey) include the new runs.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-upgrade.svg" alt="Upgrade notes" height="35"></h2>

- **The footer row is written only when it changes.** An app that draws on the last row itself must erase afterwards (`erase.all` or `tui.relayout`), which also brings the footer back.
- **Golden frames of your own pages change.** If you record golden frames with `tools/frame.sh`, the size you ask for is now honoured; re-record them once.
- **Fragment cache keys** hold style strings instead of a counter: restyling a widget only misses for that widget, and an identical widget on another page now hits. `TUI_ROWCACHE=0` still turns the cache off.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-install.svg" alt="Install or update" height="35"></h2>

```bash
dabt update                     # existing install
curl -fsSL https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/install.sh | bash   # new install
```

The full list of changes is in the [changelog](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/CHANGELOG.md).
