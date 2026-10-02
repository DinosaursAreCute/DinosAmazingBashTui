<div align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/logo-transparent.png" alt="D.A.B.T" width="560">

<h1><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/devex-update-2.svg" alt="DevEx Update 2" height="60"></h1>

<h3><em>Cleaned house, now off to the next venture</em></h3>
</div>

The first DevEx updates went after milliseconds. This one closes the house-cleaning and opens the next chapter: **pages are data now.** Templates, loops, conditionals, components and addons are in the markup, and `tui.page.refresh` rebuilds only the panes that changed. Along the way the profiler learned to hold a key: **Up/Down on the nav bar costs 47 ms of work per second of hold instead of 478, and paints 4.3 KB instead of 49.5.**

<p align="center">
<img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/release/devex-2-improvements.svg" alt="Held keys, before and after: nav bar work 478 to 47 ms per hold, Tab 420 to 60 ms, lag 8.5 to 4.5 ms and 33 to 21 ms" width="900">
</p>

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-result.svg" alt="The result" height="35"></h2>

Medians of probe-measured latency on a 150×45 terminal. A held key repeats about every 33 ms, so a repeat has to be handled well inside that; the budget for a held key is 50 ms.

**Held keys**, the same build without and with the focus work (deep runs `20261002-222307` and `20261002-223527`):

| Per second of hold | before | after | |
|---|---|---|---|
| Up/Down on the nav bar: app work | 478 ms | **47 ms** | −90% |
| Up/Down on the nav bar: bytes painted | 49.5 KB | **4.3 KB** | −91% |
| Up/Down on the nav bar: lag per press | 8.5 ms | **4.5 ms** | −47% |
| Tab: app work | 420 ms | **60 ms** | −86% |
| Tab: bytes painted | 60.7 KB | **15.9 KB** | −74% |
| Tab: lag per press | 33.2 ms | **21.2 ms** | −36% |
| List, table, page keys, cursor, typing | 2.5 to 7.3 ms | 2.6 to 6.6 ms | within noise |

Arrow-key focus search on a page of widgets went from 80 to 8 ms per hold (trace attribution).

**Against v0.0.22** (deep run `20261001-230749` and the newest deep run `20261002-223527`). This is the part to read carefully:

| | v0.0.22 | v0.0.23 | |
|---|---|---|---|
| Page switch, first visit | 143 ms | 151 ms | +6% (budget 150) |
| Page switch, revisit | 125 ms | 141 ms | +13% (budget 100) |
| Page switch by key, all ten pages | 101 ms | 108 ms | +7% |
| Page switch between trivial pages | 87 ms | 97 ms | +13% |
| Warm start | 290 ms | 347 ms | +20% |
| Cold start | 2.83 s | 3.38 s | +20% |
| Terminal resize | 203 ms | 145 ms | −29% |
| Wheel scroll | 18 ms | 16 ms | −12% |
| Idle repaints | 2.0 /s | 2.0 /s | unchanged |

Stage 2 made page switches and start-up slower, by 6 to 20%. Addon files are now part of a page's cache signature and composition runs on every build; the floor of a refresh with nothing changed is about 27 ms (see the [design page](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/docs/concepts/pages-templates-addons-refresh.md)). The newest run was taken while the demo was being edited and tested on the same machine, so read the page-switch rows as an upper bound. The command palette close reads 47 ms in both runs of this build against 13 ms in v0.0.22: a clock tick inside the profiler's settle window inflates some samples, and it is not resolved. Winning the page switch back is the next venture.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-new.svg" alt="What is new" height="35"></h2>

- **Reuse in pages.** `<template>`, `<use>`, `<slot>`, `<fill>`, `<component name src>`, `<for each|count>`, `<if test>`/`<else>` and `<include src p="v"/>` with `{{@p}}` parameters. They expand when a page loads, so the built page has only plain tags.
- **Addons.** `<addon id target priority>` files with `append`, `prepend`, `before`, `after`, `replace`, `remove`, `set` and `wrap`, read from the app's `addons` folder and from folders given to `tui.addon.dir`.
- **`tui.page.refresh`.** Re-applies addons to the page on screen and rebuilds only the panes whose content changed. Nothing changed: 27 ms; one addon: about 45 ms. The result equals a full load (unit-tested).
- **Background jobs.** `tui.job.run`, `tui.job.cancel`, `tui.job.running`: work in a background process with a spinner after a configurable delay, a done function that draws the result in one go, and `tui.page.rebuild` to build a page in the background.
- **Focus and hit zones.** `tab_order`, `tabbable`, `focusable`, `focus_group`, `focus_nav`, `focus_wrap`, `autofocus`, `hit_pad`, `hitbox`, a per-row zone index, and mouse events that carry the zone.
- **Paint pipeline.** Targeted redraws are diffed against the last flush row by row, redraws coalesce to one flush per loop pass, and the line canvas has a junction table for every border style.
- **The Compose demo page.** One realistic page instead of two: a project board with three tabs. *Board* generates task cards from one template (nested `<if>` for status, owner and priority) and lets you add, complete, block, remove and reset tasks. *Conditionals* shows `==`, `!=`, truthy values, `<else>` and nesting live, next to the markup that does it. *Addons* applies the five example addons. Every action writes an addon file and refreshes the page; switching tabs swaps the whole view the same way. Open it with `alt+-` or from the command bar.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-what-changed.svg" alt="What changed" height="35"></h2>

- **A focus move paints what it knows is dirty.** `tui.focus` draws the old and the new widget, plus the border of a pane only when the keyboard pane changes, as one raw frame. It used to redraw the pane border on every move, even inside one pane, and run every frame through a row diff (about 105 of 120 ms of a flush). The nav bar stays inside one pane, so a hold repaints two widgets.
- **Arrow-key search reads cached rects.** `tui.action.focus_dir` took every focusable widget's position from `_tui._widget_pos` on every press. It now reads the rects the hit index already computed, and rebuilds them only when the layout or a widget changes.
- Widgets nested in a pane start on its first line (row 0). Shift+Tab with nothing focused starts at the last widget. A pane that scrolls only vertically has no bottom-row scrollbar zone, and a widget's click area is clipped to its pane.
- The page parser finds the end of a tag with one regex, and `tui.cache.deps_of` and the `<include>` lookup no longer fork. The node store lists each node's attribute names, so clone, remove and parameter substitution visit only the attributes they need.
- The demo's header and menu are templates in `share/demo/_templates.xml`; the `_header.xml` and `_nav.xml` fragments are gone.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-fixed.svg" alt="Fixed along the way" height="35"></h2>

- **Boxes that checked themselves on hover.** `tui.set` stores a widget's value but does not redraw it. A visit callback that used it on a visible checkbox or input showed stale state until the mouse hovered the widget: on the old Addons page the boxes of addons applied in an earlier run looked unchecked, then flipped on hover. The demo pages use `tui.update` (store and redraw); two regression tests.
- `${v//a/&...}` on bash 5.2+ treats `&` as "the matched text": template parameters containing `&` and the `wx` attribute rebuild now quote the replacement.
- `<if>` branches sharing a widget id removed the kept branch from the id index; an addon folder that was both registered and the app's own was read twice and reported as an include cycle; the validator demanded `pane` and `row` on widgets nested in a pane.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-tools.svg" alt="New tools" height="35"></h2>

- **Hold a key in the profiler.** `tools/profiler/profile.sh --scenario held` sends one press every 33 ms for holds of 0.1 s to 1 s on the nav bar, a list, a table, an input, Tab and PgDn. Per press it reports the queue time, the lag from the key sent to the first output the terminal receives (so widgets that draw outside the flush count too) and the render cadence. The rating uses the worst press, not the first paint.
- **`--scenario compose`** profiles the refresh paths of the Compose page: open, add a task, switch tab, change a conditional, apply the five addons. In the first quick run these took 160 to 320 ms against their 100 ms budgets; that is the work for the next update.
- **The explorer and journey** include the new deep runs, the held-key groups and the stage 2 cost.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-upgrade.svg" alt="Upgrade notes" height="35"></h2>

- **The Generated and Addons demo pages are one page, Compose.** Anything that opened `generated.xml` or `addons.xml` (a command, a binding, a profiler scenario of your own) must point at `compose.xml`. The example addons now target `compose.xml`.
- **Use `tui.update`, not `tui.set`, to change a widget that is already on screen** from a visit or action callback; `tui.set` alone does not redraw.
- **Golden frames of the demo change** where a focus move used to be two flushes and is now one (`widgets.frame`, 16 bytes of synchronised-output markers); re-record your own once with `tools/t_golden.sh`.
- A `<select>`, `<password>`, `<textarea>`, `<list>`, `<table>` or `<progress>` nested in a pane gets "missing id or pane" today: give it an explicit `pane=`. A fix is on the list.

<h2><img src="https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/assets/headers/release-install.svg" alt="Install or update" height="35"></h2>

```bash
dabt update                     # existing install
curl -fsSL https://raw.githubusercontent.com/DinosaursAreCute/DinosAmazingBashTui/main/install.sh | bash   # new install
```

The full list of changes is in the [changelog](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/CHANGELOG.md).
