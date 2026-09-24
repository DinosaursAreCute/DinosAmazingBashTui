# Developer API

The public surface of D.A.B.T, one page per module - each mirrors a `lib/` topic directory, the way a Javadoc package-summary page mirrors a Java package. Every function also has a page of its own (`api/<module>/<function>`), linked from the summary table on its module page; the module page shows the same entries one after another. Use the search in the header (or press `/`) to find a function by name across every page at once; it's pre-scoped to "This section" when you're already inside `api/`, with an "Everywhere" toggle to search the whole site. For how the pieces fit together see the [documentation index](../README.md).

| Module | Covers | Mirrors |
|---|---|---|
| **[Core](core.md)** | Lifecycle, layout (panes), tabs, factory widgets, content/output, `tui.exec`, live updates, getters, logging/perf, event & result variables | `lib/tui.sh`, `lib/tui_api.sh`, `lib/state.sh` |
| **[Style](style.md)** | Themes | `lib/style/` |
| **[Input](input.md)** | Key/mouse bindings, built-in actions | `lib/input/` |
| **[Widgets](widgets.md)** | Widget constructors, richer widgets & text editing | `lib/widgets/` |
| **[Chrome](chrome.md)** | Command palette, modal/overlay, dialogs & toasts, footer | `lib/chrome/` |
| **[Markup](markup.md)** | Pages, cache & validation | `lib/markup/` |
| **[Config](config.md)** | Persisted settings | `lib/config/` |
| **[Plugins](plugin.md)** | Plugins & hooks, app metadata | `lib/plugin/`, `lib/tui_home.sh` |
| **[Apps](apps.md)** | Installing and running apps, updating DABT, file sync, security scan | `lib/apps/` |
| **[Renderers](renderers.md)** | Standalone box/table/chart/banner renderers | `lib/terminal_renderer.sh` |
| **[Terminal controls](terminal-controls.md)** | ~310 escape-sequence helpers (generated) | `lib/terminal_controls.sh` |
| this page | Task-oriented tour with examples, below | |

Rules of the road: call only public functions (`tui.*`, renderers, `cur.*`/`mode.*`/...); never `_tui.*`, `_exec_*`, `_tr_*` or any leading-underscore name. Callbacks are plain bash functions whose first argument is the id of the widget that fired (`action="on_save"` → `on_save btn_save`). Checkboxes add the new value (`fn ID 0|1`), inputs the submitted text (`fn ID TEXT`), so one function can serve several widgets ([Widgets](widgets.md)).

## 1. Start an app

```bash
#!/usr/bin/env bash
TUI_APP_NAME=my_app                       # config + log folder (~/.config/DABT/apps/my_app/)
source /path/to/lib/tui.sh
tui.cmd.load "$APP/commands.xml"          # optional: your commands in the command bar
tui.start "$APP/config/home.xml"          # init + load + run + cleanup
```

`tui.start_cached` does the same after pre-warming every sibling page. Pages, includes and callbacks: [../guide/markup.md](../guide/markup.md). → reference: [Lifecycle](core.md#lifecycle).

## 2. Build layout in code (instead of, or next to, XML)

```bash
tui.hsplit root nav:1 main:3
tui.vsplit main top:2 bottom:1
tui.pane_title main "Dashboard"; tui.pane_border main double; tui.pane_pad main 1 1
tui.grid bottom 1 3 pack "" "" a b c        # 1 row × 3 cols
tui.fixed keys 6 3 esc f1 f2 space:4        # every child 6×3 cells, space is 4 units wide
```

XML equivalents and the grid/tab details: [../guide/grid-layouts-and-tabs.md](../guide/grid-layouts-and-tabs.md). → [Layout](core.md#layout-panes).

## 3. Widgets and forms

```bash
tui.label  lbl_name form 0 "Name"
tui.input  inp_name form 1 "type here" "Name:" on_name_submit   # on_name_submit inp_name TEXT
tui.checkbox chk_a form 2 "Enable" 1 on_toggle       # on_toggle chk_a 0|1
tui.button btn_go  form 3 "[ Save ]" on_save

on_save() {
    local name; name="$(tui.get inp_name)"
    tui.set_label btn_go "[ Saved: $name ]"
}
```

Inputs keep focus after Enter by default (`tui.input.retain ID false` to drop it). Use `tui.update ID VALUE` to change a value and redraw. Runtime-built forms: `tui.factory.*` (`tui.factory.grid demo grid_pane 6 3; tui.factory.button demo "$_TUI_FACTORY_LAST_ID"...`, then `tui.factory.clear demo`). → [Widgets](widgets.md#widgets), [Factory](core.md#factory-runtime-widgets), [Tabs](core.md#tabs).

### Text editing and data widgets

```bash
tui.textarea notes editor 0 "notes..." 0            # multi-line, fills its pane; click, drag-select, ctrl+arrows, cut/paste, undo
tui.on_change notes mark_dirty                      # after every edit
tui.password pw form 1 "password" "Pass:" do_login
tui.list files side 0 open_file 8; tui.list.set files a.txt b.txt c.txt
tui.table t data 0 "" 0; tui.table.set t "Name|Size" "a.txt|1k" "b.txt|2k"
tui.select mode form 3 "Mode:" mode_changed; tui.select.set mode fast balanced careful
tui.progress job form 5 "Job:"; tui.progress.set job 40
```

Key tables, mouse behaviour and the Markdown roadmap: [../guide/widgets.md](../guide/widgets.md). -> [Richer widgets](widgets.md#richer-widgets).

## 4. Put content in panes

```bash
tui.output log "line one" "line two"           # replace
tui.output_append log "another line"           # append
some_command | tui.output log                  # from stdin
tui.output stats "$(table_string 'A|B' '1|2')" # renderer output is just text with ANSI
tui.pane_scroll log v                          # wheel / j k / drag scrollbar
```

For anything updated in a loop use `tui.set_text PANE TEXT` (fork-free, redraws only on change). Long-running processes: `tui.exec "ping -c3 host" out_pane ctl_pane` streams live through a PTY; several can share a pane. Scrolling internals: [../design/viewport-scrolling.md](../design/viewport-scrolling.md), viewport tips: [../guide/callbacks-and-viewports.md](../guide/callbacks-and-viewports.md). → [Content](core.md#content-and-output), [tui.exec](core.md#process-streaming-tuiexec).

## 5. Live, continuously updating things

```bash
tui.clock hdr_clock "%H:%M:%S" seg3            # big live clock
tui.every 2 refresh_stats                       # refresh_stats stats_id, every 2 s
tui.watch out "df -h /" 5                       # run off-thread, show stdout
tui.monitor mon_pane 1                          # CPU/MEM/SWAP/load dashboard

refresh_stats() {
    tui.sys.cpu; tui.sys.mem
    tui.set_text stats "CPU ${TUI_SYS_CPU}%  MEM ${TUI_SYS_MEM_PCT}%"
}
```

Timers share one tick listener, cost no fork per update and are cleared on page change. Custom per-frame work: `tui.tick.add my_fn` (never overwrite `_TUI_TICK_FN`). → [Live updates](core.md#live-updates).

## 6. Read state

```bash
read -r rows cols <<< "$(tui.get.dimensions content_pane --content)"
tui.get.dimensions -c                    # terminal columns
tui.get.focused; tui.get.hovered pane; tui.get.scroll log
tui.get.class.style brand fg             # theme value without a pane
```

Inside a handler `TUI_EVENT_KEY`, `TUI_EVENT_X/Y`, `TUI_EVENT_PANE`, `TUI_EVENT_WIDGET` describe the event. → [Getters](core.md#getters), [Variables](core.md#event-and-result-variables).

## 7. Style and themes

```css
/* theme.css */
.nav_link          { fg: cyan; }
.nav_link:focus    { fg: BLACK; bg: #61afef; mods: bold; }
```

```bash
tui.class btn_go nav_link              # or class="nav_link" in XML
tui.theme.set "$APP/themes/ocean.css"  # app-wide overlay over every page's own theme
tui.class.sgr nav_link focus; printf '%s text\e[0m' "$TUI_SGR"
```

Reference of selectors and properties: [../guide/markup.md#styling](../guide/markup.md#styling). → [Styling and themes](style.md#styling-and-themes).

## 8. Keys, mouse, actions

```bash
tui.bind ctrl+e on_export --desc "Export"          # global
tui.bind mouse:right on_ctx --pane output          # only in that pane
tui.bind ctrl+s on_save --always                   # fires even while typing in an input
tui.defaults.off wheel                             # opt out of a default group (whole app)
tui.keys.suspend_key ctrl+g                        # change the kill-switch key
tui.bind.save                                      # persist user (--user) binds
```

Default bindings live in `share/defaults/keybinds.xml`, grouped and opt-out. Full model (lookup order, `--pass`, repeat coalescing, pass-through mode, paste): [../guide/input-bindings.md](../guide/input-bindings.md). → [Input](input.md#input-and-bindings), [Actions](input.md#built-in-actions).

## 9. Command bar, modals, dialogs, footer

```bash
tui.cmd.add export "Export report" on_export --group App --desc "Write report.csv" --key ctrl+e
tui.cmd.provider my_page_commands        # my_page_commands calls tui.cmd.add each time the palette opens

# a modal: draw fn + key fn
my_draw() { tui.overlay.box 5 10 40 "1;97;44" "Confirm" "Delete file?" "[y] yes   [n] no"; }
my_keys() { case "$1" in y) do_delete; tui.modal.close ;; n|esc) tui.modal.close ;; esac; }
tui.modal.open confirm my_keys my_draw
```

```xml
<footer items="@tui.action.quit|Quit;@tui.palette.open|Command bar;ctrl+s|Save"/>
```

`@ACTION` items show whichever key is currently bound to the action. Defaults and the shipped Settings/Keybinds pages: [../guide/input-bindings.md](../guide/input-bindings.md). → [Commands](chrome.md#commands-and-palette), [Modal](chrome.md#modal-and-overlay), [Footer](chrome.md#footer).

### Dialogs and toasts

```bash
tui.confirm "Delete report.csv?" do_delete --danger --yes Delete --no Keep      # do_delete runs only on Yes
tui.prompt "New name:" do_rename --value "$old" --validate name_ok              # do_rename NEWNAME
tui.choose "Export as" do_export csv json yaml                                  # do_export INDEX ITEM
tui.notify "Report saved" success                                               # toast, gone after 5 s

name_ok() { [[ -n "$1" && "$1" != */* ]] || { TUI_DIALOG_ERROR="no slashes, not empty"; return 1; }; }
do_rename() { mv "$old" "$1" && tui.notify "Renamed to $1" success || tui.notify "Rename failed" error 6; }
```

Dialogs never block: they return at once and call your function afterwards, so a callback can open the next dialog (prompt then confirm). `tui.config.set confirm.quit 1` makes every quit ask first. → [Dialogs and notifications](chrome.md#dialogs-and-notifications).

## 10. Pages, history, persisted settings

```bash
tui.goto "$APP/config/settings.xml"     # switch page (history kept)
tui.action.back                         # previous page
tui.config.set my.option on             # ~/.config/DABT/apps/my_app/dabt.conf
tui.config.get my.option off            # with default
tui.action.goto_default settings        # DABT's shipped Settings page (also in the palette)
```

Pages are recorded and replayed from a cache keyed on file mtimes (page + includes); why and how: [../design/write-ahead-logging-and-replay.md](../design/write-ahead-logging-and-replay.md). → [Pages and cache](markup.md#pages), [Config](config.md#persisted-config).

## 11. Plugins

```bash
tui.plugin.list                     # what was detected
tui.plugin.enable hello             # sources ~/.config/DABT/plugins/hello.plugin.sh and runs plugin.hello.on_enable
tui.plugin.disable hello            # its commands, keys, hooks and timers are removed again
tui.hook.on page my_page_hook       # react to every page switch
```

A plugin file, where DABT keeps its files, hooks and the built-in terminal_shortcuts plugin: [../guide/plugins.md](../guide/plugins.md). -> [Plugins](plugin.md#plugins).

## 12. Renderers without the TUI

`source lib/terminal_renderer.sh` gives you `box`, `table`, `linechart`, `banner`... in any script. See [renderers.md](renderers.md) and `examples/csv-charts/`.
