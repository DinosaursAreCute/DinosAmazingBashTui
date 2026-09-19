# Developer API

The public surface of D.A.B.T, grouped by task with short examples. For a flat lookup of every function and parameter use **[reference.md](reference.md)**. For how the pieces fit together see the [documentation index](../README.md).

| Page | Contents |
|---|---|
| [reference.md](reference.md) | Every public function, parameters, description (one table per area). |
| [renderers.md](renderers.md) | `box`, `table`, charts, `banner`... standalone renderers. |
| [terminal-controls.md](terminal-controls.md) | All ~310 escape-sequence helpers (generated). |
| this page | Task-oriented tour with examples. |

Rules of the road: call only public functions (`tui.*`, renderers, `cur.*`/`mode.*`/...); never `_tui.*`, `_exec_*`, `_tr_*` or any leading-underscore name. Callbacks are plain bash functions that receive the widget id (`action="on_save"` → `on_save btn_save`).

## 1. Start an app

```bash
#!/usr/bin/env bash
TUI_APP_NAME=my_app                       # config namespace (~/.config/my_app/)
source /path/to/bin/tui.sh
tui.cmd.load "$APP/commands.xml"          # optional: your commands in the command bar
tui.start "$APP/config/home.xml"          # init + load + run + cleanup
```

`tui.start_cached` does the same after pre-warming every sibling page. Pages, includes and callbacks: [../guide/markup.md](../guide/markup.md). → reference: [Lifecycle](reference.md#lifecycle).

## 2. Build layout in code (instead of, or next to, XML)

```bash
tui.hsplit root nav:1 main:3
tui.vsplit main top:2 bottom:1
tui.pane_title main "Dashboard"; tui.pane_border main double; tui.pane_pad main 1 1
tui.grid bottom 1 3 pack "" "" a b c        # 1 row × 3 cols
tui.fixed keys 6 3 esc f1 f2 space:4        # every child 6×3 cells, space is 4 units wide
```

XML equivalents and the grid/tab details: [../guide/grid-layouts-and-tabs.md](../guide/grid-layouts-and-tabs.md). → [Layout](reference.md#layout-panes).

## 3. Widgets and forms

```bash
tui.label  lbl_name form 0 "Name"
tui.input  inp_name form 1 "type here" "Name:" on_name_submit
tui.checkbox chk_a form 2 "Enable" 1 on_toggle       # on_toggle chk_a 0|1
tui.button btn_go  form 3 "[ Save ]" on_save

on_save() {
    local name; name="$(tui.get inp_name)"
    tui.set_label btn_go "[ Saved: $name ]"
}
```

Inputs keep focus after Enter by default (`tui.input.retain ID false` to drop it). Use `tui.update ID VALUE` to change a value and redraw. Runtime-built forms: `tui.factory.*` (`tui.factory.grid demo grid_pane 6 3; tui.factory.button demo "$_TUI_FACTORY_LAST_ID"...`, then `tui.factory.clear demo`). → [Widgets](reference.md#widgets), [Factory](reference.md#factory-runtime-widgets), [Tabs](reference.md#tabs).

## 4. Put content in panes

```bash
tui.output log "line one" "line two"           # replace
tui.output_append log "another line"           # append
some_command | tui.output log                  # from stdin
tui.output stats "$(table_string 'A|B' '1|2')" # renderer output is just text with ANSI
tui.pane_scroll log v                          # wheel / j k / drag scrollbar
```

For anything updated in a loop use `tui.set_text PANE TEXT` (fork-free, redraws only on change). Long-running processes: `tui.exec "ping -c3 host" out_pane ctl_pane` streams live through a PTY; several can share a pane. Scrolling internals: [../design/viewport-scrolling.md](../design/viewport-scrolling.md), viewport tips: [../guide/callbacks-and-viewports.md](../guide/callbacks-and-viewports.md). → [Content](reference.md#content-and-output), [tui.exec](reference.md#process-streaming-tuiexec).

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

Timers share one tick listener, cost no fork per update and are cleared on page change. Custom per-frame work: `tui.tick.add my_fn` (never overwrite `_TUI_TICK_FN`). → [Live updates](reference.md#live-updates).

## 6. Read state

```bash
read -r rows cols <<< "$(tui.get.dimensions content_pane --content)"
tui.get.dimensions -c                    # terminal columns
tui.get.focused; tui.get.hovered pane; tui.get.scroll log
tui.get.class.style brand fg             # theme value without a pane
```

Inside a handler `TUI_EVENT_KEY`, `TUI_EVENT_X/Y`, `TUI_EVENT_PANE`, `TUI_EVENT_WIDGET` describe the event. → [Getters](reference.md#getters), [Variables](reference.md#event-and-result-variables).

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

Reference of selectors and properties: [../guide/markup.md#styling](../guide/markup.md#styling). → [Styling and themes](reference.md#styling-and-themes).

## 8. Keys, mouse, actions

```bash
tui.bind ctrl+e on_export --desc "Export"          # global
tui.bind mouse:right on_ctx --pane output          # only in that pane
tui.bind ctrl+s on_save --always                   # fires even while typing in an input
tui.defaults.off wheel                             # opt out of a default group (whole app)
tui.keys.suspend_key ctrl+g                        # change the kill-switch key
tui.bind.save                                      # persist user (--user) binds
```

Default bindings live in `config/default/keybinds.xml`, grouped and opt-out. Full model (lookup order, `--pass`, repeat coalescing, pass-through mode, paste): [../guide/input-bindings.md](../guide/input-bindings.md). → [Input](reference.md#input-and-bindings), [Actions](reference.md#built-in-actions).

## 9. Command bar, modals, footer

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

`@ACTION` items show whichever key is currently bound to the action. Defaults and the shipped Settings/Keybinds pages: [../guide/input-bindings.md](../guide/input-bindings.md). → [Commands](reference.md#commands-and-palette), [Modal](reference.md#modal-and-overlay), [Footer](reference.md#footer).

## 10. Pages, history, persisted settings

```bash
tui.goto "$APP/config/settings.xml"     # switch page (history kept)
tui.action.back                         # previous page
tui.config.set my.option on             # ~/.config/my_app/dabt.conf
tui.config.get my.option off            # with default
tui.action.goto_default settings        # DABT's shipped Settings page (also in the palette)
```

Pages are recorded and replayed from a cache keyed on file mtimes (page + includes); why and how: [../design/write-ahead-logging-and-replay.md](../design/write-ahead-logging-and-replay.md). → [Pages and cache](reference.md#pages-and-cache), [Config](reference.md#persisted-config).

## 11. Renderers without the TUI

`source bin/terminal_renderer.sh` gives you `box`, `table`, `linechart`, `banner`... in any script. See [renderers.md](renderers.md) and `examples/csv-charts/`.
