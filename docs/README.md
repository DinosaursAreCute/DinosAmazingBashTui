# D.A.B.T documentation

DinosAmazingBashTui is a terminal UI framework in **pure bash** (5.0+) plus POSIX utilities and `awk`. No Python, Node or ncurses.
This page is the map: how the framework is put together, and where to look for what.

## Where to look

| I want to... | Read |
|---|---|
| Build a page from XML (panes, grids, tabs, includes, themes) | [guide/markup.md](guide/markup.md) |
| Understand grids and tabs in depth | [guide/grid-layouts-and-tabs.md](guide/grid-layouts-and-tabs.md) |
| Write callbacks, hover/focus feedback and scrolling viewports | [guide/callbacks-and-viewports.md](guide/callbacks-and-viewports.md) |
| Bind keys and mouse, use the command bar, footer, default pages | [guide/input-bindings.md](guide/input-bindings.md) |
| Look up **any function and its parameters** | [api/reference.md](api/reference.md) (one big table) |
| Read the API grouped by topic, with examples | [api/README.md](api/README.md) |
| Use the renderers (box, table, charts, banner...) without the TUI | [api/renderers.md](api/renderers.md), [examples/csv-charts](../examples/csv-charts/README.md) |
| Know why scrolling / hover / caching are built the way they are | [design/](#design-write-ups) |
| See what changed | [../CHANGELOG.md](../CHANGELOG.md) |
| Profile or screenshot the demo | [../bin/debug/README.md](../bin/debug/README.md) |

Fastest start: copy `config/DABT_demo/home.xml` + `bin/DABT_demo.sh`, then read [guide/markup.md](guide/markup.md).

## High-level architecture

```
 your app                       framework                                   terminal
 ────────                       ─────────                                   ────────
 page.xml  ──tui.load/goto──▶  tui_markup.sh  ──tui.* builder calls──▶  tui.sh  ──ANSI──▶  tty
 page_callbacks.sh ◀─actions──  (parser, page cache)                     (state, layout,
 theme.css ──────────────────▶  tui_style.sh (class → colours)            input, render loop)
                                tui_input.sh / tui_cmd.sh / tui_modal.sh / tui_footer.sh
                                tui_api.sh (public helpers: getters, timers, clocks, monitors)
                                terminal_renderer.sh (box, table, charts... standalone)
                                terminal_controls.sh + colors.sh (raw ANSI, no state)
```

### Layers (load order in `bin/tui.sh`)

| Layer | File | Job |
|---|---|---|
| Terminal primitives | `terminal_controls.sh`, `colors.sh` | Cursor, erase, SGR, modes, mouse, OSC. Stateless one-liners that print escape sequences. |
| Markup | `tui_markup.sh` | Parses XML pages into `tui.*` calls. `tui.start FILE` = init + load + run + cleanup. `tui.goto` switches page. |
| Style | `tui_style.sh` | `theme.css` (`.class`, `:focus`, `:hover`, `:border`, `:title`) resolved to fg/bg/mods per pane/widget. |
| Core | `tui.sh` | Pane tree + layout engine (`hsplit`/`vsplit`/`grid`/`fixed`), widgets, focus, mouse routing, render (AWK "shader" viewports), main loop, `tui.exec`. |
| Input | `tui_input.sh` | Key/mouse binding tables, dispatch, defaults (`config/default/keybinds.xml`), paste, focus movement, user keybind persistence. |
| Commands | `tui_cmd.sh`, `tui_modal.sh`, `tui_footer.sh` | Command registry + palette, overlay/modal layer, `<footer/>` key-hint bar. |
| Config | `tui_config.sh` | Persisted framework settings (`~/.config/<app>/dabt.conf`). |
| Cache | `tui_cache.sh` | Page record/replay cache, stylesheet memo, on-disk cache, warm-up. |
| Public helpers | `tui_api.sh` | Getters, live helpers (`tui.every`, `tui.clock`, `tui.watch`, `tui.monitor`), theme overlay, style helpers. |
| Renderers | `terminal_renderer.sh` | `box`, `table`, `hbar`, `linechart`, `banner`... each with a printing and a `_string` form. Usable with no TUI at all. |

### What happens when a page loads

1. `tui.goto page.xml` (or `tui.start`) → `tui.load_cached`. If the page's call log is cached and its files (page + includes) are unchanged it is **replayed**; otherwise the XML is parsed once and recorded.
2. The parser/replay issues builder calls: `tui.hsplit`, `tui.label`, `tui.button`, `tui.pane_border`, `tui.footer.set`, `tui.bind`... Nothing is drawn yet.
3. `<script>` files are sourced, the theme is applied, then layout runs (`_tui._layout`) and `on_visit` fires.
4. `tui.render` draws every pane, widget and content buffer inside one synchronized-output frame (`mode.sync_start/end`).
5. Overlays (footer, modal/palette, kill-switch box) are drawn on top after each flushed frame.

### The main loop (`tui.run`)

One loop iteration reads input (`read -t`, keyboard + SGR mouse), decodes it into an event (`TUI_EVENT_*`), and dispatches through the binding tables. Then it flushes any debounced render, runs `_TUI_TICK_FN`, redraws overlays (only after a frame was flushed) and calls every listener registered with `tui.tick.add`. `tui.every`, `tui.clock`, `tui.watch`, `tui.monitor` and `tui.exec` all ride one shared tick listener, so a page can run many live things without owning the loop.

### Input dispatch

`user binds → code binds (tui.bind, <bind>) → framework defaults (config/default/keybinds.xml)`, first match wins. Defaults are grouped (`focus`, `pane`, `scroll`, `click`, `wheel`, ...) and opt-out per app or page (`tui.defaults.off GROUP`). Details: [guide/input-bindings.md](guide/input-bindings.md).

### Design rules that shape the code

- **No external dependencies.** POSIX utilities + `awk` only.
- **Subshells are a last resort.** `$(...)` is a fork (~1 ms), so hot paths use `printf -v`, here-strings, namerefs, `EPOCHREALTIME` and `read < file`. Builders that would return text through a subshell have `_v` variants that write a result variable.
- **Redraw only what changed.** Content is change-detected (`tui.set_text`), scroll/content redraws are debounced, and overlays redraw only after a real frame.
- **Public vs private.** `tui.*`, `mode.*`, `cur.*` ... are public. Anything starting with `_` (`_tui.*`, `_exec_*`, `_tr_*`, `_tui_input.*`) is private: never call it from callbacks or config.
- **Multi-instance `tui.exec`.** Never assume one process per pane; instances are keyed `e1`, `e2`, ...
- **Page-level work uses `tui.tick.add`.** `_TUI_TICK_FN` is a legacy single slot; overwriting it breaks concurrent `tui.exec`.
- **Callbacks stay thin.** A callback is a plain bash function that calls public `tui.*` functions.

## App layout

```
my_app/
  bin/run.sh                 source tui.sh; TUI_APP_NAME=my_app; tui.start config/home.xml
  config/
    home.xml  other.xml      pages (HTML-like)
    _nav.xml                 shared fragment, <include src="_nav.xml"/>
    home_callbacks.sh        functions referenced by action="..." / on_visit="..."
    theme.css                <theme src="theme.css"/>
    themes/*.css             optional app-wide theme overlays (Settings / palette pick from here)
```

`config/DABT_demo/` is a complete working app. The framework's own defaults live in `config/default/` (`keybinds.xml`, `commands.xml`, `theme.css`, `pages/` for the built-in Settings and Keybinds pages); override the directory with `TUI_DEFAULTS_DIR`.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `TUI_APP_NAME` | `dabt` | Config namespace: user keybinds in `~/.config/$TUI_APP_NAME/keybinds.xml`, settings in `dabt.conf` next to it. |
| `TUI_DEFAULTS_DIR` | `config/default` | Where default keybinds, commands, theme and shipped pages are read from. |
| `TUI_THEMES_DIR` | `<app dir>/themes` | Themes offered by Settings and the palette. |
| `TUI_USER_KEYBINDS` | `~/.config/$TUI_APP_NAME/keybinds.xml` | Saved user keybinds file. |
| `TUI_CONFIG_FILE` | `~/.config/$TUI_APP_NAME/dabt.conf` | Persisted framework settings. |
| `TUI_FOOTER_DEFAULT` | quit, command bar, back | Default `<footer/>` items. |
| `TUI_INPUT_RETAIN_ON_SUBMIT` | `true` | Whether inputs keep focus after Enter (per input: `tui.input.retain`). |
| `TR_WIDTH` | terminal width | Renderers: force the width they lay out to (e.g. a pane's width). |
| `TUI_MOUSE_DRAIN_PEEK_TIMEOUT` | small, **> 0** | Mouse-motion coalescing peek. Never set to 0 (`read -t 0` consumes nothing). |

## Design write-ups

Long-form explanations of the non-obvious performance decisions. Read them before reimplementing scrolling, hover or caching.

| Document | Topic |
|---|---|
| [design/viewport-scrolling.md](design/viewport-scrolling.md) | Why scrolling is an AWK "shader" and how to keep wheel/drag fast. |
| [design/pointer-tracking-and-hover.md](design/pointer-tracking-and-hover.md) | Low-latency mouse tracking and hover resolution. |
| [design/grid-geometry-and-widget-factories.md](design/grid-geometry-and-widget-factories.md) | Grid geometry, container abstractions and runtime widget factories. |
| [design/write-ahead-logging-and-replay.md](design/write-ahead-logging-and-replay.md) | The page cache: recording builder calls and replaying them deterministically. |
| [design/rebindable-input-and-developer-ergonomics.md](design/rebindable-input-and-developer-ergonomics.md) | The 0.0.6 UX/DevX decisions: bindings as data, opt-out defaults, command bar, overlays, focus, live helpers. |

## Debugging and tooling

`bin/debug/` holds the profiling and screenshot tools (page-switch timings, per-call fork counts, full profile, PNG screenshots of every page and theme); see [../bin/debug/README.md](../bin/debug/README.md). `.tui_exec.log` is the runtime debug log written by `tui.log*`.
