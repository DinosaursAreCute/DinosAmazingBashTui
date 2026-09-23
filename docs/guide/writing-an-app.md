# Writing a DABT application

Technical reference for building, structuring, packaging and shipping an application on DABT. New to all of this? Start with the tutorial [Writing Your First App](../tutorials/writing-your-first-app.md); this page is the precise version. Function tables: [../api/](../api/). Tag reference: [markup.md](markup.md).

Contents: [Anatomy](#anatomy) · [The entry script](#the-entry-script) · [Application identity and state](#application-identity-and-state) · [Pages](#pages) · [Callbacks](#callbacks) · [State and persistence](#state-and-persistence) · [Live content](#live-content) · [Input, commands, footer](#input-commands-footer) · [Dialogs and messages](#dialogs-and-messages) · [Themes](#themes) · [Plugins in your app](#plugins-in-your-app) · [Packaging](#packaging-and-distribution) · [Testing](#testing) · [Rules and pitfalls](#rules-and-pitfalls)

## Anatomy

```
my_app/
├── .dabt.metadata           name, version, entry ... read by `dabt app install`
├── my_app.sh                entry script (the only thing that is executed)
├── plugins/                 optional: plugins that belong to this app (discovered automatically)
└── config/
    ├── home.xml  other.xml  pages
    ├── _nav.xml             a fragment: <include src="_nav.xml"/> (a leading _ keeps it out of the page cache warm-up)
    ├── home_callbacks.sh    functions for action= / submit= / on_visit=
    ├── theme.css            classes for class="..."
    └── themes/*.css         optional app-wide theme overlays
```

Three kinds of files, three responsibilities - keep them apart:

| File | Responsibility | Never |
|---|---|---|
| `*.xml` | structure: panes, widgets, ids, which callback, which class | contain logic |
| `*_callbacks.sh` | logic: read widgets, change data, update widgets | build layout, call `_tui.*` internals |
| `theme.css` | appearance | be required (an unstyled class renders plain) |

A complete tiny app: [`examples/first-app/`](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/examples/first-app/). A large one: [`share/demo/`](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/share/demo/).

## The entry script

```bash
#!/usr/bin/env bash
APP_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# 1. find DABT: `dabt app run` exports TUI_ROOT; run by hand, resolve it through the dabt command
if [[ -z "${TUI_ROOT:-}" ]] && command -v dabt >/dev/null 2>&1; then
    _dabt="$(readlink -f "$(command -v dabt)")"; TUI_ROOT="$(cd -P "$(dirname "$_dabt")/.." && pwd -P)"
fi
[[ -r "${TUI_ROOT:-}/lib/tui.sh" ]] || { echo "myapp: DABT not found. Install it first." >&2; exit 1; }

# 2. identity, BEFORE sourcing tui.sh
TUI_APP_NAME="${TUI_APP_NAME:-myapp}"
TUI_APP_TITLE="My App"; TUI_APP_DESC="What it does"; TUI_APP_ENTRY="myapp.sh"

# 3. load the framework, then your own setup (optional), then run
source "$TUI_ROOT/lib/tui.sh"
tui.start "$APP_DIR/config/home.xml"
```

`tui.start FILE` = `tui.init` + `tui.load` + `tui.run` + guaranteed terminal restore (also on error or signal). `tui.start_cached FILE` additionally pre-warms the page cache for every sibling `*.xml` behind the logo/progress screen and serves later `tui.goto` calls from it - use it for apps with many pages. Use the pieces (`tui.init`, `tui.load FILE`, `tui.run`) only when you need code between them.

Do custom setup (extra config, `tui.cmd.load commands.xml`, `_TUI_THEME_OVERLAY=...`, hooks) **after** `source` and **before** `tui.start`.

## Application identity and state

Set before sourcing `tui.sh`:

| Variable | Meaning |
|---|---|
| `TUI_APP_NAME` | id: `a-z 0-9 . _ -`. Names the state folder. Default `dabt`. |
| `TUI_APP_TITLE`, `TUI_APP_DESC`, `TUI_APP_ENTRY` | shown by `dabt app info`, written to `app.meta` |

After `tui.init` these are available:

| Variable | Value |
|---|---|
| `TUI_APP_CONF` | `~/.config/DABT/apps/$TUI_APP_NAME/` - **your** data folder. Survives `dabt app update` and `remove` (unless `--purge`). |
| `TUI_HOME` | `~/.config/DABT` (see `lib/tui_home.sh`) |
| `TUI_ROOT` | the program folder (the framework) |
| `_TUI_APP_DIR` | the folder of the first page the app started with (`themes/` is looked up there) |

Files DABT keeps in `$TUI_APP_CONF`: `dabt.conf` (framework + plugin settings), `keybinds.xml` (the user's key changes), `app.meta`. Add your own (`settings.conf`, data files). `tui.config.get|set KEY [VALUE]` is the key/value store behind `dabt.conf`; use your own file for your own domain data.

## Pages

A page is an XML file (one tag per line, `"double quoted"` attributes). Root `<tui>`:

```xml
<tui on_visit="home_visit">                       <!-- called every time the page opens -->
  <script src="home_callbacks.sh"/>               <!-- sourced; relative to THIS file -->
  <theme src="theme.css"/>
  <footer items="@tui.action.quit"/>
  <include src="_nav.xml"/>                       <!-- shared fragment, inlined at parse time -->
  <bind key="alt+1" action="tui.action.goto home.xml" desc="Home"/>     <!-- page-scoped key -->
  ...panes, then widgets...
</tui>
```

**Panes** form a tree; **widgets** attach to a pane by `pane="id"` and a `row`. Splits: `split="h"` (children side by side), `split="v"` (stacked), `split="grid"`, `split="fixed"`; children size by `weight`. Scrolling text panes: `scroll="v|h|both"` and must be leaf panes ([callbacks-and-viewports.md](callbacks-and-viewports.md)). Tabs and grids: [grid-layouts-and-tabs.md](grid-layouts-and-tabs.md). Widgets: `label`, `button`, `input`, `checkbox`, `list`, `table`, `select`, `textarea`, `progress` ([widgets.md](widgets.md)).

**Navigation.** `<button ... page="other.xml"/>` goes to a page; from code `tui.goto other.xml`, or bind `tui.action.goto other.xml`. `tui.action.back` returns. Switching resets the UI (`tui.reset_ui`: panes, widgets, timers, footer and page binds are wiped and rebuilt) but keeps history.

**Lifecycle of a page load:**

1. `tui.goto`/`tui.start` → the page is loaded from the cache if it and its includes are unchanged, otherwise parsed and recorded ([write-ahead-logging-and-replay.md](../design/write-ahead-logging-and-replay.md)).
2. Builder calls create panes/widgets; nothing is drawn yet.
3. `<script>` files are sourced, the theme applied, layout computed.
4. `on_visit` fires; the first frame is drawn; the event loop runs.

Consequences: `<script>` files are sourced **on every page load** - top-level code in a callbacks file runs again, so initialise state either in `on_visit` or guarded (`declare -p X >/dev/null 2>&1 || X=...`); and the page cache is keyed on the files' content, so editing an XML file while developing just works.

## Callbacks

A callback is a bash function named in `action=`, `submit=`, `on_change=`, `on_visit=` or bound to a key. Contract:

- It is called with the widget id (buttons: `fn ID`; checkboxes: `fn ID VALUE`; list/table `action` and `on_change`: see [widgets.md](widgets.md)). Ignore arguments you do not need.
- Exit status has no protocol. Return quickly: the UI is single-threaded, a slow callback freezes the screen. Long work goes to `tui.exec` / `tui.watch` (below).
- Read: `tui.get ID`, `tui.list.selected ID`, `tui.table.row ID`. Write: `tui.update ID VALUE`, `tui.set_text PANE TEXT` (change-detected, use in loops), `tui.output`/`tui.output_append PANE TEXT` (scroll panes), `tui.list.set|add|clear`, `tui.table.set`. Move focus: `tui.focus ID`.
- Only public `tui.*` (and `mode.*`, `cur.*`, renderers). Never `_tui.*`, `_exec_*`, `_tr_*`.
- Inside a key/mouse handler `TUI_EVENT_TYPE|KEY|X|Y|PANE|WIDGET|BUTTON` describe the event (`tui.get.event`).
- Rendered strings: use the `*_string` renderer variants (`table_string`, `alert_string` ...) and pass `printf '%b'` output to `tui.output`.

The recurring shape: **mutate state → re-render from state.**

```bash
on_add() {
    local t; t="$(tui.get inp_task)"
    [[ -n "${t// }" ]] || { tui.notify "Type something" warn 2; return; }
    TASKS+=("$t"); _save; _show          # data first, then screen
    tui.update inp_task ""
}
```

## State and persistence

- **In memory:** globals in the callbacks file (`declare -ga TASKS=()`). They live as long as the app process; they are **not** reset by page changes (but re-sourcing a file re-runs its top level - see above).
- **On disk:** files under `$TUI_APP_CONF`. Write atomically for anything important (`> file.tmp && mv -f file.tmp file`). Framework-level settings: `tui.config.set KEY VALUE` (saved immediately to `dabt.conf`).
- **Arrays:** `unset 'ARR[i]'` leaves a hole - re-pack with `ARR=("${ARR[@]}")` before handing to `tui.list.set`. To show an empty list call `tui.list.clear ID` instead of `tui.list.set ID` with no items.
- Values with `|` break `tui.table.set` rows (the separator); strip or replace them.

## Live content

| Need | Use |
|---|---|
| call a function every N seconds | `tui.every SEC FN [ID]`. **Runs once immediately, then every interval.** Cancel with `tui.every.cancel ID`. Page-scoped: cleared on page change. |
| once, later | `tui.after SEC FN [ID]` |
| a clock in a pane | `tui.clock PANE [FMT] [FONT]` |
| a shell command's output in a pane, refreshed | `tui.watch PANE CMD [SEC]` (runs off-thread) |
| a long-running/streaming process | `tui.exec` (PTY-backed, multi-instance, capped ring buffer) |
| CPU/mem/disk gauges | `tui.monitor` |
| your own per-frame work | `tui.tick.add FN` |

`tui.every`, `tui.clock`, `tui.watch`, `tui.monitor` and `tui.exec` share one tick listener. Never overwrite `_TUI_TICK_FN` (legacy single slot); use `tui.tick.add`. Do not add direct `tui.render` calls in hot paths - `tui.update`/`tui.set_text` already redraw only what changed.

## Input, commands, footer

```bash
tui.bind ctrl+e on_export --desc "Export"        # global; --pane ID scopes it; --pass runs the default afterwards
tui.cmd.add app.export "Export data" on_export --group App --key ctrl+e   # command bar (ctrl+p)
tui.cmd.load "$APP_DIR/config/commands.xml"       # or declare them as <cmd .../> lines
```

Lookup order: user binds → code binds (`tui.bind`, `<bind>`) → framework defaults (`share/defaults/keybinds.xml`). While a text input has focus, typing keys skip bindings unless bound `--always`. Names: `ctrl+c`, `alt+x`, `shift+tab`, `f1..f12`, `mouse:left`, `wheel:up` ... ([input-bindings.md](input-bindings.md)). The footer (`<footer items="..."/>`, `tui.footer.*`) shows key hints; `@tui.action.NAME` items are resolved from the current bindings.

## Dialogs and messages

| Call | Result |
|---|---|
| `tui.notify MSG [info\|success\|warn\|error] [SEC]` | toast, non-blocking |
| `tui.confirm MSG YES_FN [NO_FN] [--danger --yes L --no L --title T]` | yes/no modal |
| `tui.message MSG [ON_CLOSE_FN]` | OK modal |
| `tui.prompt MSG SUBMIT_FN [--placeholder T]` | text prompt; `SUBMIT_FN VALUE` |
| `tui.choose TITLE FN ITEM... [--message T]` | pick from a list; `FN INDEX ITEM` |
| `tui.view TITLE TEXT [--width N]` | scrollable read-only text (plain, no colors) |

Dialogs are asynchronous: the call returns immediately and your callback runs later. Continue your flow inside the callback, never after the call. One dialog at a time; opening another replaces it.

## Themes

`theme.css` defines `.class { fg; bg; mods }` plus `:hover` (widgets), `:focus` (widgets and pane borders), `:border`, `:title`. Colors: a `colors.sh` name or `#RRGGBB`. `mods`: `bold underline ...`. Themes stack: framework defaults → page theme → `_TUI_THEME_OVERLAY` (a whole-app overlay, e.g. the user's pick from `themes/*.css`). Unknown classes are harmless. Runtime: `tui.class.style|sgr CLASS [STATE]`. See [markup.md](markup.md#tui_stylesh) and [callbacks-and-viewports.md](callbacks-and-viewports.md#2-hover-and-focus-feedback).

## Plugins in your app

Every DABT app supports plugins with no code from you: user plugins in `~/.config/DABT/plugins/`, built-ins from `share/plugins/`, and your own from `<app folder>/plugins/` (discovered automatically; shown as source `app` in Settings > Plugins). Hooks you can rely on from your side: `init`, `ready`, `page FILE`, `resize`, `key NAME`, `quit`, `exit`. To disable plugins entirely set `TUI_NO_PLUGINS=1`. Writing plugins: [../tutorials/writing-your-first-plugin.md](../tutorials/writing-your-first-plugin.md), [plugins.md](plugins.md).

## Packaging and distribution

`.dabt.metadata` (key = value, `#` comments) next to the entry script:

| Key | |
|---|---|
| `name` | required; lowercase id (`dabt` is reserved) |
| `entry` | required; script to start, relative to the app folder |
| `version`, `title`, `description`, `author` | optional |
| `own_dir` | `yes` = live in `~/.local/share/dabt-apps/NAME`; default `no` = in `~/.config/DABT/apps/NAME` |
| `min_dabt`, `max_dabt` | supported DABT versions (inclusive) |
| `install_hook`, `uninstall_hook` | scripts run by bash after install/update and before removal (env: `DABT_HOOK`, `DABT_APP_NAME`, `DABT_APP_DIR`, `DABT_APP_CONF`, `DABT_APP_VERSION`); a failing hook only warns |

```bash
dabt app install ./my_app | https://github.com/you/my_app[#ref]   # security-scanned first
dabt app run NAME | list | info NAME | update [NAME] | remove NAME [--purge]
```

Install flags: `--strict` refuses on HIGH scan findings, `--no-scan` skips the scan, `--force`, `--name`, `--entry`. Updates replace everything in the app folder **except** `dabt.conf keybinds.xml settings.conf app.meta terminal_shortcuts.*`. Write your data to `$TUI_APP_CONF`, never into the app folder.

`dabt scan PATH... [--deep] [--strict]` runs the same scan yourself; keep your app clean of `curl | sh`, `eval` of variables, writes to system paths, and hard-coded credentials, since users see the findings when they install it.

## Testing

TUI behaviour has to be seen in a real terminal, `bash bin/DABT_demo.sh`. For automation, run under a pseudo-terminal with a fixed size and a sandboxed home, so tests never touch real settings:

```bash
H=$(mktemp -d)
{ sleep 2; printf 'buy milk\r'; sleep 1; printf 'q'; sleep 1; } |
  timeout 15 script -qfec "stty rows 30 cols 100; env HOME=$H XDG_CONFIG_HOME=$H/c TERM=xterm-256color bash my_app.sh" /dev/null
cat "$H/c/DABT/apps/myapp/tasks.txt"        # assert on the files the app wrote
```

Assert on **state** (files, config) rather than on screen text. A terminal shorter than your layout needs (about 24 rows is a sensible minimum) clips panes: size weights so that `head`-style strips still have room for their rows at 24×80. Framework tests: `bats tests/`.

## Rules and pitfalls

- **No dependencies** beyond bash 5, POSIX utilities and `awk`. If you reach for another tool, reconsider.
- **Private is private.** `_tui.*`, `_exec_*`, `_tr_*`, `_tui_input.*` and anything with a leading underscore in the framework may change between releases.
- **Set `TUI_APP_NAME` before `source tui.sh`**, or your state lands in the default `dabt` folder and mixes with other apps.
- **`tui.every` fires once immediately** - guard if the first call would be wrong.
- **Callbacks files are re-sourced per page load**: no unguarded state initialisation at top level.
- **Dialogs are asynchronous**: put the follow-up in the callback.
- **Scrolling panes must be leaves** (no child panes or widgets); update them with `tui.output`/`tui.set_text`, not by drawing.
- **Do not call `tui.render` in hot paths**, and never set `TUI_MOUSE_DRAIN_PEEK_TIMEOUT` to 0.
- **`tui.exec` is multi-instance**: never assume one process per pane.
- **Escape sequences in strings**: renderers return strings with real ANSI; `tui.output` wants resolved `\n`/escapes (`printf '%b'`). Text you show must not contain raw user-controlled escape sequences.
- **Clean shutdown** is `tui.start`'s job; do not `exit` from inside a callback - call `tui.action.quit` (or `tui.stop`).
