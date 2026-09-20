# API reference

Every public function in one place. `[x]` = optional, `A|B` = choose one, `NAME...` = repeatable. Functions are called as plain bash functions; most return status via exit code (0 = success) and print/return values as noted. Anything starting with `_` is private and not listed.

Conventions:
- **ID** = widget id, **PANE** = pane id, **FN** = name of a bash function, **KEY** = key spec (`ctrl+q`, `shift+up`, `wheel:down`, `mouse:left`, ... see [../guide/input-bindings.md](../guide/input-bindings.md)).
- "→ `VAR`" means the result is left in a global variable instead of printed (fork-free).
- Topic pages with examples: [README.md](README.md).

Sections: [Lifecycle](#lifecycle) · [Layout](#layout-panes) · [Widgets](#widgets) · [Tabs](#tabs) · [Factory](#factory-runtime-widgets) · [Content](#content-and-output) · [Process streaming](#process-streaming-tuiexec) · [Live updates](#live-updates) · [Getters](#getters) · [Styling and themes](#styling-and-themes) · [Input and bindings](#input-and-bindings) · [Actions](#built-in-actions) · [Commands and palette](#commands-and-palette) · [Modal and overlay](#modal-and-overlay) · [Footer](#footer) · [Config](#persisted-config) · [Pages and cache](#pages-and-cache) · [Logging and perf](#logging-and-perf) · [Renderers](#renderers) · [Terminal controls](#terminal-controls) · [Variables](#event-and-result-variables)

## Lifecycle

| Function | Parameters | Description |
|---|---|---|
| `tui.start` | `FILE` | Full lifecycle: init, load page, run loop, guaranteed cleanup. The usual entry point. |
| `tui.start_cached` | `FIRST_PAGE` | Like `tui.start`, but first pre-warms the page cache for every sibling `*.xml` (with a progress bar). |
| `tui.init` | | Enter raw mode, alt screen, mouse tracking; load config, defaults. Called by `tui.start`. |
| `tui.run` | | Main loop: input → dispatch → render → ticks. Returns after `tui.stop`. |
| `tui.stop` | | Ask the main loop to exit (also `tui.action.quit`). |
| `tui.cleanup` | | Restore the terminal (mouse, paste mode, screen, stty). Called automatically. |
| `tui.require` | `terminal_renderer\|terminal_controls` | Source an optional module once (idempotent). |
| `tui.tick.add` | `FN` | Register `FN` to be called every loop iteration. Page work goes here, never in `_TUI_TICK_FN`. |
| `tui.tick.remove` | `FN` | Unregister a tick listener. |
| `tui.on_resize` | | Mark the terminal as resized (installed as the SIGWINCH handler). |

## Layout (panes)

Panes form a tree rooted at `root`. Children are given as `NAME[:WEIGHT]` (weight default 1).

| Function | Parameters | Description |
|---|---|---|
| `tui.hsplit` | `PARENT NAME[:W]...` | Split PARENT into side-by-side children. |
| `tui.vsplit` | `PARENT NAME[:W]...` | Split PARENT into stacked children. |
| `tui.grid` | `PARENT ROWS COLS [FIT] [ROW_WEIGHTS] [COL_WEIGHTS] NAME...` | Grid of ROWS×COLS cells; all six leading params are positional (pass `""` to skip a weight list). FIT = `pack` (default; blank cells stay as empty panes) or `stretch` (a row's blank cells are absorbed by its neighbours). Weights are space-separated. |
| `tui.fixed` | `PARENT SIZE_W SIZE_H CHILD[:SPAN[:nl]]...` | Fixed-size grid: every child is exactly SIZE_W×SIZE_H cells (× SPAN wide), flowed and wrapped; `:nl` forces a row break. |
| `tui.pane_title` | `PANE TEXT` | Title drawn in the top border. |
| `tui.pane_border` | `PANE none\|single\|double\|heavy\|...` | Border style (explicit; parents lose it when there is no room). |
| `tui.pane_pad` | `PANE HPAD VPAD` | Blank cols/rows inside the pane. On a parent: gap between frame and children. On a leaf: shrinks the widget/output area. |
| `tui.pane_align` | `PANE left\|center\|right\|fill` | Default horizontal alignment of widgets in the pane. |
| `tui.pane_valign` | `PANE top\|middle\|bottom` | Vertical alignment of the pane's content. |
| `tui.pane_minsize` | `PANE [MINW] [MINH]` | Minimum size; below it the pane shows a "min space" notice instead of its content. |
| `tui.pane_maxsize` | `PANE [MAXW] [MAXH]` | Maximum size. |
| `tui.pane_scroll` | `PANE none\|v\|h\|both` | Enable scrolling (resets the offsets). |
| `tui.pane_strict_fit` | `PANE true\|false` | Turn the content-fit warning on/off for a pane. |
| `tui.pane_size` | `PANE` | → `TUI_PANE_ROWS`, `TUI_PANE_COLS` (usable content size). |
| `tui.content_area` | `PANE` | Prints `ROW COL H W` of the content rectangle. |
| `tui.pane.focus` | `PANE` | Give keyboard pane focus (scroll target, highlighted border). |
| `tui.relayout` | `[PANE]` | Recompute geometry and repaint in one sync frame. With a leaf: repaint only that pane. |
| `tui.clear_pane` | `PANE` | Blank a pane's rectangle. |
| `tui.render` / `tui.redraw` | | Repaint everything now (one synchronized frame). |

## Widgets

Constructors take `ID PANE ROW ...`. Missing ID/PANE prints an error and skips the widget.

| Function | Parameters | Description |
|---|---|---|
| `tui.label` | `ID PANE ROW TEXT` | Static text. |
| `tui.button` | `ID PANE ROW TEXT [ACTION_FN]` | Focusable button; `ACTION_FN ID` runs on Enter/click. |
| `tui.input` | `ID PANE ROW [PLACEHOLDER] [LABEL] [SUBMIT_FN]` | Single-line input; `SUBMIT_FN ID` runs on Enter. |
| `tui.checkbox` | `ID PANE ROW LABEL [CHECKED] [ACTION_FN]` | Checkbox; CHECKED = `1\|true\|yes`; `ACTION_FN ID VALUE` gets `0`/`1`. |
| `tui.checkbox.toggle` | `ID` | Flip a checkbox, redraw, call its action. |
| `tui.get` | `ID` | Print a widget's value (input text, checkbox `0/1`, label text). |
| `tui.set` | `ID VALUE` | Set a value without redrawing. |
| `tui.update` | `ID VALUE` | Set a value and redraw the widget. |
| `tui.set_label` | `ID TEXT` | Change a button/checkbox caption (or label text) and redraw. |
| `tui.get.label` | `ID` | Print the caption. |
| `tui.on_action` | `ID FN` | Set/replace the action callback. |
| `tui.on_submit` | `ID FN` | Set/replace an input's submit callback. |
| `tui.align` | `ID left\|center\|right\|fill` | Horizontal alignment of a widget. |
| `tui.valign` | `ID top\|middle\|bottom` | Vertical alignment. |
| `tui.minsize` / `tui.maxsize` | `ID WIDTH` | Min/max widget width. |
| `tui.pad` | `ID [HPAD] [VPAD]` | Padding around a widget. |
| `tui.label_align` | `ID left\|right` | Alignment of an input's label. |
| `tui.label_width` | `ID N` | Fixed label column width (line inputs up). |
| `tui.input.retain` | `ID [true\|false]` | "Retain Input On Submit": keep focus after Enter (default true). |
| `tui.input.blur_on_submit` | `ID` | Old name for `tui.input.retain ID false`. |
| `tui.input.sticky` | `ID [true\|false]` | Keep focus through repaints and page reloads. |
| `tui.focus` | `ID` | Focus a widget (its pane becomes the keyboard pane). |

## Tabs

| Function | Parameters | Description |
|---|---|---|
| `tui.tabs.compact` | `TABS_ID [true\|false]` | Call before `build`: single-row header instead of framed cells. |
| `tui.tabs.add` | `TAB_ID TEXT ACTION [DEFAULT]` | Register a tab (ACTION runs when it is activated). |
| `tui.tabs.build` | `TABS_ID HEADER_PANE CONTENT_PANE TAB_ID...` | Build the header row and activate the default (or first) tab. |
| `tui.tabs.activate` | `TAB_ID` | Make a tab active: focuses its header and calls its action. |

## Factory (runtime widgets)

Namespaced constructors for layouts whose shape is only known at runtime. Each leaves the generated id in `_TUI_FACTORY_LAST_ID`.

| Function | Parameters | Description |
|---|---|---|
| `tui.factory.label` | `NS PANE ROW TEXT` | Auto-id label. |
| `tui.factory.button` | `NS PANE ROW TEXT [ACTION]` | Auto-id button. |
| `tui.factory.input` | `NS PANE ROW [PLACEHOLDER] [LABEL] [SUBMIT]` | Auto-id input. |
| `tui.factory.checkbox` | `NS PANE ROW LABEL [CHECKED] [ACTION]` | Auto-id checkbox. |
| `tui.factory.grid` | `NS PARENT COUNT [COLS] [FIT] [ROW_WEIGHTS] [COL_WEIGHTS]` | Grid of COUNT cells (auto-square if COLS omitted); cell ids in `_TUI_FACTORY_GRID_CELLS`. |
| `tui.factory.clear` | `NS` | Tear down everything built under NS. |

## Content and output

| Function | Parameters | Description |
|---|---|---|
| `tui.output` | `PANE [TEXT...]` | Replace the pane's content. Without TEXT reads stdin (`... \| tui.output pane`). Multi-line text is split on newlines; ANSI allowed. |
| `tui.output_append` | `PANE [TEXT...]` | Append lines (or stdin). |
| `tui.output_clear` | `PANE` | Empty the pane and repaint. |
| `tui.set_text` | `PANE TEXT` | Fork-free, change-detected `tui.output` (unchanged text is not redrawn). Use for anything updated in a loop. |

## Process streaming (`tui.exec`)

| Function | Parameters | Description |
|---|---|---|
| `tui.exec` | `CMD OUT_PANE [CTL_PANE]` | Run CMD in a PTY and stream its output into OUT_PANE. With CTL_PANE you get Cancel/Save/View/Retry/Back buttons and a stdin box. Multi-instance: several may target one pane. |
| `tui.exec.cancel_pane` | `PANE` | Cancel and dismiss every instance targeting PANE. |

## Live updates

All ride one shared tick listener; no fork per update; output is change-detected; jobs are cleared on page change (`tui.reset_ui`) and exit.

| Function | Parameters | Description |
|---|---|---|
| `tui.every` | `SEC FN [ID]` | Call `FN ID` every SEC (decimals ok, minimum 0.05). ID defaults to FN. |
| `tui.after` | `SEC FN [ID]` | Call `FN ID` once after SEC. |
| `tui.every.cancel` | `ID` | Remove a timer. |
| `tui.every.pause` / `tui.every.resume` | `ID` | Pause/resume a timer. |
| `tui.every.clear` | | Remove all timers. |
| `tui.every.list` | | Print `ID<TAB>INTERVALms<TAB>FN` per timer. |
| `tui.clock` | `PANE [FMT] [FONT] [ID]` | Live clock in PANE. FMT = strftime (default `%H:%M:%S`), FONT = banner font (`block5 seg3 box3 blk3 half2`) or empty. |
| `tui.watch` | `PANE CMD [SEC] [ID]` | Run CMD every SEC (default 2) in one background producer and show stdout in PANE, like `watch`; the UI never blocks. |
| `tui.watch.stop` | `ID` | Stop a watch. |
| `tui.watch.now` | `ID` | Restart the producer so the next frame arrives immediately. |
| `tui.monitor` | `PANE [SEC] [ID]` | Ready-made CPU/MEM/SWAP/load dashboard. |
| `tui.sys.cpu` | | → `TUI_SYS_CPU` (percent since the last call). |
| `tui.sys.mem` | | → `TUI_SYS_MEM_PCT`, `_USED_MB`, `_TOTAL_MB`, `TUI_SYS_SWAP_PCT`. |
| `tui.sys.load` | | → `TUI_SYS_LOAD1`, `_LOAD5`, `_LOAD15`. |
| `tui.sys.uptime` | | → `TUI_SYS_UPTIME` (s), `TUI_SYS_UPTIME_STR`. |
| `tui.hist.push` | `NAME VALUE [MAX]` | Append to a rolling sample series (default MAX 60). |
| `tui.hist.get` | `NAME` | Print the series (space separated). |

## Getters

Read-only, print to stdout unless stated. Pane getters return 1 for an unknown pane.

| Function | Parameters | Prints |
|---|---|---|
| `tui.get.dimensions` | `[-r\|--rows] [-c\|--columns] [--content] [PANE]` | `ROWS COLS` of the terminal, or of PANE (`--content`: usable area). `-r`/`-c` print one number. |
| `tui.get.terminal` | | `ROWS COLS` of the terminal. |
| `tui.get.position` | `PANE` | `ROW COL` of its top-left. |
| `tui.get.rect` | `PANE` | `ROW COL H W`. |
| `tui.get.content_area` | `PANE` | `ROW COL H W` of the content rectangle. |
| `tui.get.border` | `PANE` | Effective border style. |
| `tui.get.title` | `PANE` | Title. |
| `tui.get.pad` | `PANE` | `HPAD VPAD`. |
| `tui.get.split` | `PANE` | `h`, `v`, `grid` or empty. |
| `tui.get.children` | `PANE` | Child ids. |
| `tui.get.parent` | `PANE` | Parent id. |
| `tui.get.panes` | `[leaves]` | All pane ids (or only leaves). |
| `tui.get.lines` | `PANE` | Number of content lines. |
| `tui.get.scroll` | `PANE` | `MODE V_OFFSET H_OFFSET LINES MAX_WIDTH`. |
| `tui.get.style` | `ID FIELD [STATE]` | `fg`, `bg` or `mods` of a pane/widget. |
| `tui.get.widgets` | `[PANE]` | Widget ids (in draw order). |
| `tui.get.type` | `ID` | `label\|button\|input\|checkbox`. |
| `tui.get.pane` | `ID` | The widget's pane. |
| `tui.get.action` | `ID` | The widget's action function. |
| `tui.get.checked` | `ID` | Status only: 0 if a checked checkbox. |
| `tui.get.focused` | | Focused widget id. |
| `tui.get.hovered` | `[widget\|pane]` | Hovered widget (default) or pane. |
| `tui.get.pane_focus` | | Keyboard-focus pane. |
| `tui.get.page` | | Current page file. |
| `tui.get.pages` | | `NAME<TAB>FILE` of every registered page. |
| `tui.get.event` | | `type=… key=… x=… y=… pane=… widget=… button=…` of the current event. |
| `tui.get.classes` | | Every key of the loaded theme. |
| `tui.get.class.style` | `CLASS FIELD [STATE]` | `fg\|bg\|mods` of a theme class (no pane needed). |

## Styling and themes

STATE = `normal` (default) `focus border title hover checked unchecked` (the last two apply to checkboxes); a state without rules falls back to normal.

| Function | Parameters | Description |
|---|---|---|
| `tui.load_theme` | `FILE` | Load a `theme.css` (memoized by mtime). |
| `tui.class` | `ID CLASS` | Apply `.CLASS` (+ `:focus/:border/:title/:hover`) to a widget or pane. |
| `tui.style` | `ID FG BG MODS [STATE]` | Low-level style setter (FG/BG: color name or `#rrggbb`; MODS: `bold dim italic underline reverse ...`). |
| `tui.ansi` | `ID [STATE]` | Print the ANSI prefix of an id's style. |
| `tui.class.ansi` | `CLASS [STATE]` | Same, straight from a theme class. |
| `tui.paint` | `ID TEXT [STATE]` | Print TEXT wrapped in the id's style + reset. |
| `tui.class.paint` | `CLASS TEXT [STATE]` | Same for a class. |
| `tui.style.sgr` | `ID [STATE]` | Fork-free → `TUI_SGR TUI_FG TUI_BG`. |
| `tui.class.style` | `CLASS [STATE]` | → `TUI_FG TUI_BG TUI_MODS`. |
| `tui.class.sgr` | `CLASS [STATE]` | → `TUI_SGR` (+ the three above), fork-free. |
| `tui.class.names` | | → `TUI_CLASSES` array (sorted). |
| `tui.theme.set` | `FILE` | Layer FILE over every page's own theme, app-wide; reloads the page. |
| `tui.theme.clear` | | Remove the overlay. |
| `tui.theme.current` | | Print the overlay file. |
| `tui.theme.reload` | | Reload the current page. |
| `tui.cache.theme_clear` | | Forget every memoized stylesheet. |

## Input and bindings

| Function | Parameters | Description |
|---|---|---|
| `tui.bind` | `KEY COMMAND [--pane ID] [--pass] [--always] [--page] [--user] [--desc TEXT]` | Bind KEY. `--pane`: only when that pane is keyboard/pointer target. `--pass`: run this, then the default binding too. `--always`: also fire while typing in an input. `--page`: cleared on page change. `--user`: a user bind (persisted by `tui.bind.save`). COMMAND may chain with `;`. |
| `tui.unbind` | `KEY [--pane ID] [--user]` | Remove a binding. |
| `tui.bind.reset` | `[--user]` | Drop all code binds, or (`--user`) all user binds. |
| `tui.bind.list` | | Print bind rows. |
| `tui.bind.table` | | → `_TBL` aligned text table of all bindings. |
| `tui.bind.defaults` | `[FILE]` | (Re)load default binds (default `config/default/keybinds.xml`). |
| `tui.defaults.off` | `GROUP... [--page]` | Turn default groups off (`--page`: this page only). |
| `tui.defaults.on` | `GROUP...` | Turn groups back on. |
| `tui.defaults.list` | | Print each group with on/off and its keys. |
| `tui.bind.save` | `[FILE]` | Persist user binds (default `~/.config/$TUI_APP_NAME/keybinds.xml`). |
| `tui.bind.load` | `[FILE]` | Load user binds. |
| `tui.bind.discard` | | Reload the saved file, dropping unsaved changes. |
| `tui.bind.dirty` | | Status 0 if user binds differ from the saved file. |
| `tui.bind.saved_file` | | Print the saved-binds path. |
| `tui.keys.suspend` | `[on\|off\|toggle]` | Kill-switch: disable keyboard bindings (shows a warning box). |
| `tui.keys.suspend_key` | `KEY` | Change the kill-switch key. |
| `tui.keys.suspended` | | Status 0 while suspended. |
| `tui.passthrough` | `[on\|off\|toggle]` | Hand keyboard and mouse back to the terminal (native selection/copy). |
| `tui.passthrough.key` | `KEY` | Change the pass-through toggle key. |
| `tui.passthrough.active` | | Status 0 while active. |
| `tui.clipboard.copy` | `TEXT` | Copy via OSC 52 (kitty, foot, wezterm, alacritty, iTerm2, tmux). |
| `tui.clipboard.paste` | | Print the last bracketed paste. |

## Built-in actions

Use as `COMMAND` in `tui.bind`, `<bind action="…">`, `<button action="…">` or `tui.cmd.add`.

| Action | Parameters | Description |
|---|---|---|
| `tui.action.quit` | | Stop the app. |
| `tui.action.focus_next` / `tui.action.focus_prev` | | Next / previous widget. |
| `tui.action.focus_dir` | `up\|down\|left\|right` | Spatial widget navigation (nearest in that direction). |
| `tui.action.unfocus` | | Leave the focused widget. |
| `tui.action.activate` | | Enter on the focused widget (press, toggle, submit). |
| `tui.action.click` | | Left press/drag: scrollbar jump, else activate widget under pointer, else drop focus. |
| `tui.action.scroll` | `up\|down\|left\|right [N]` | Scroll the target pane by N (default 3 lines / 5 chars; merged repeats multiply). |
| `tui.action.page` | `up\|down` | One viewport. |
| `tui.action.scroll_top` / `tui.action.scroll_bottom` | | Jump to start/end. |
| `tui.action.pane_next` / `tui.action.pane_prev` | | Cycle keyboard pane focus. |
| `tui.action.pane_dir` | `up\|down\|left\|right` | Nearest pane in that direction. |
| `tui.action.focus_pane` | `PANE` | Focus a pane (its last/first widget, else make it the scroll target). |
| `tui.action.paste` | | Insert `TUI_EVENT_PASTE` into the focused input. |
| `tui.action.goto` | `PAGE_FILE` | Go to a page. |
| `tui.action.goto_default` | `settings\|keybinds` | Open a page shipped with DABT (`config/default/pages/`). |
| `tui.action.back` | | Return to the previous page. |
| `tui.action.reload_page` | | Reload the current page. |
| `tui.action.redraw` | | Full relayout and repaint. |

## Commands and palette

The command bar (default `ctrl+p`) lists registered commands and runs one.

| Function | Parameters | Description |
|---|---|---|
| `tui.cmd.add` | `ID TITLE ACTION [--group G] [--desc D] [--when FN] [--key KEY]` | Register a command. `--when FN`: only listed while `FN` succeeds. `--key`: also bind a key. Re-adding an ID replaces it. |
| `tui.cmd.remove` | `ID` | Unregister. |
| `tui.cmd.run` | `ID` | Run a command by id. |
| `tui.cmd.list` | | Print `ID GROUP TITLE ACTION` per command. |
| `tui.cmd.load` | `FILE` | Load `<cmd .../>` lines (same style as `config/default/commands.xml`). |
| `tui.cmd.provider` | `FN` | Register a dynamic provider: `FN` calls `tui.cmd.add` each time the palette opens (e.g. one command per theme or page). |
| `tui.palette.open` | `[QUERY]` | Open the palette (optionally prefilled). |
| `tui.palette.close` | | Close it. |

## Modal and overlay

An overlay is a draw function called after every flushed frame (so it stays on top). A modal is an overlay that also captures input.

| Function | Parameters | Description |
|---|---|---|
| `tui.overlay.add` | `DRAWFN` | Register an overlay draw function. |
| `tui.overlay.remove` | `DRAWFN` | Remove it. |
| `tui.overlay.box` | `ROW COL WIDTH SGR TITLE LINE...` | Draw a framed box in place (SGR like `1;97;44`). For DRAWFNs. |
| `tui.modal.open` | `NAME KEYFN DRAWFN [MOUSEFN]` | Open a modal: `KEYFN KEY` gets every key (and `paste`); `MOUSEFN NAME X Y` gets mouse events. |
| `tui.modal.close` | | Close and repaint everything under it. |
| `tui.modal.active` | `[NAME]` | Status 0 if a modal (optionally NAME) is open. |
| `tui.modal.redraw` | | Redraw overlays now. |

## Footer

| Function | Parameters | Description |
|---|---|---|
| `tui.footer.set` | `ITEMS` | Declare the footer (what `<footer items="…"/>` calls). Records state only. |
| `tui.footer.show` | `[ITEMS]` | Set and show, with relayout (the root pane gives up the last row). |
| `tui.footer.add` | `KEY LABEL [WHEN_FN]` | Append an item. |
| `tui.footer.hide` | | Remove the footer. |

ITEMS = `KEY|Label[|WHEN_FN];…`. KEY may be literal (`ctrl+s`) or `@ACTION` (shows the key currently bound to that action, so rebinding updates the footer). `WHEN_FN` hides the item while it fails.

## Persisted config

Small key/value store for framework settings (`~/.config/$TUI_APP_NAME/dabt.conf`), applied at `tui.init`. Known keys: `theme`, `defaults.off`, `input.retain`.

| Function | Parameters | Description |
|---|---|---|
| `tui.config.get` | `KEY [DEFAULT]` | Print a value. |
| `tui.config.set` | `KEY VALUE` | Set and save. |
| `tui.config.unset` | `KEY` | Remove and save. |
| `tui.config.load` / `tui.config.save` | | Read / write the file. |
| `tui.config.apply` | | Apply the loaded settings to the running framework. |

## Pages and cache

| Function | Parameters | Description |
|---|---|---|
| `tui.load` | `FILE` | Parse a markup file and build panes/widgets. |
| `tui.goto` | `FILE` | Switch page: reset UI, load (cached), keep history and focus. |
| `tui.reset_ui` | | Wipe panes, widgets, timers, modal, footer, page binds; rebuild an empty `root`. |
| `tui.load_cached` | `FILE` | Drop-in `tui.load` that replays a valid cached page. |
| `tui.cache.valid` | `FILE` | Status 0 if the page and all its includes are unchanged since recorded. |
| `tui.cache.record` | `FILE` | Load with recording on and store the call log. |
| `tui.cache.replay` | `FILE` | Rebuild a page from its call log. |
| `tui.cache.signature` | `FILE...` | `path=mtime;…` string for a file set. |
| `tui.cache.deps_of` | `FILE ARRAYNAME` | Append FILE and its (recursive) includes to an array. |
| `tui.cache.dump_dir` / `tui.cache.load_dir` | `DIR` | Write / read recorded pages (invalid entries dropped on load). |
| `tui.cache.disk_dir` | | Print the persistent cache dir (`.cache/tui_pages/`). |
| `tui.cache.warm_with_spinner` | `PAGE...` | Pre-warm pages with a banner and progress bar. |
| `tui.cache.init` | | Wrap the builder functions for recording (done once at load). |
| `tui.cache.cleanup` | | Remove the stamp directory. |

## Logging and perf

| Function | Parameters | Description |
|---|---|---|
| `tui.log` | `MSG [LEVEL]` | Append to `.tui_exec.log` (stdout is the screen, so logs go to a file). |
| `tui.log.debug` / `tui.log.info` / `tui.log.warn` / `tui.log.error` | `MSG` | Level shortcuts. |
| `tui.perf.mean_render_ms` | `SECONDS` | Mean frame time over the trailing window (needs `_TUI_PERF_TRACKING=1`; empty if no data). |

## Renderers

Standalone (`source bin/terminal_renderer.sh`, or `tui.require terminal_renderer`). Every command has a printing form `cmd ARGS` and a string form `cmd_string ARGS` (lines joined with literal `\n`, ready for `tui.output`). `TR_WIDTH=N` forces the layout width. Colors are names from `bin/colors.sh` (`RED`, `BRIGHT_CYAN`, `DIM_YELLOW`, ...). Details and examples: [renderers.md](renderers.md).

| Function | Arguments | Description |
|---|---|---|
| `box` | `"message"` | Bordered box. |
| `divider` | `["label"]` | Horizontal rule. |
| `alert` | `info\|warn\|error\|success "msg"` | Callout. |
| `table` | `"H1\|H2" "r1\|r2"...` | Data table. |
| `kv` | `"Key: Val"... [-t dots\|plain\|dashes]` | Aligned key-value list. |
| `hbar` | `"Label:Value"... [-m max] [-n min] [-w width] [-lw label_w] [-c COLORS]` | Horizontal bars. |
| `vbar` | `"Label:Value"... [-h rows] [-m] [-n] [-tw total_w] [-cw col_w] [-c COLORS]` | Vertical bars. |
| `gauge` | `VALUE [-m max] [-n min] [-l label] [-lw] [-w width] [-c COLOR]` | Single gauge. |
| `sparkline` | `"v1 v2 …" [-d delim] [-w] [-m] [-n] [-c COLOR]` | Inline trend. |
| `linechart` | `"Series:v1,v2,…"... [-h rows] [-w plot_w] [-m] [-n] [-c COLORS]` | Multi-series line chart. |
| `csv_hbar` / `csv_vbar` / `csv_linechart` | `FILE.csv [--header] [-d delim] …` (same flags as the plain chart) | Charts straight from CSV. |
| `banner` | `"TEXT" [FONT] [SCALE]` | Big letters. FONT: `block5 seg3 box3 blk3 half2`. `banner --list` shows every glyph set. |
| `banner_fonts` / `banner_list` | | Print font names / all character sets. |
| `tree` | `"root" "  child"...` | Indented tree. |
| `columns` | `[-h "Hdr"] "col1" "col2"...` | Side-by-side columns. |
| `badges` | `"pass:Build" "fail:Test"...` | Status tags. |
| `list` | `[-n] [-s "▸"] "item"...` | Bullet / numbered list. |
| `quote` | `[-a "Author"] "text"` | Block quote. |

Flag `-s` on the CLI (`bash terminal_renderer.sh box -s "hi"`) returns the string form.

## Terminal controls

`bin/terminal_controls.sh` is a flat library of escape-sequence one-liners (about 280 functions): [terminal-controls.md](terminal-controls.md) lists every one. Namespaces:

| Prefix | Covers |
|---|---|
| `cur.*` | Cursor movement, save/restore, shape, visibility. |
| `erase.*` | Erase screen/line/chars (`erase.all`, `erase.line_right`, ...). |
| `scroll.*` | Scroll regions and scrolling. |
| `mode.*` | DEC modes: alt screen, wrap, sync (`mode.sync_start/end`), bracketed paste, focus reports. |
| `mouse.*` | Mouse tracking modes and encodings (`mouse.full_on` = any-motion + SGR). |
| `style.*`, `fg.*`, `bg.*` | SGR attributes and colors (`fg.hex "#rrggbb"`, `bg.256 N`, ...). |
| `term.*` | Title, bell, notify, size and capability queries (`term.size`, `term.has_truecolor`, ...). |
| `osc.*`, `link.*`, `clip.*`, `img.*` | OSC sequences, hyperlinks, clipboard, inline images. |
| `printat ROW COL TEXT`, `sprint TEXT`, `sgr N...`, `putblock ROW COL R G B`, `clearrow ROW`, `fillrow ROW COL CHAR COUNT` | Positioned and styled printing helpers. |

## Event and result variables

| Variable | Set by | Meaning |
|---|---|---|
| `TUI_EVENT_TYPE` | dispatcher | `key`, `mouse` (wheel and drag included), `paste`. |
| `TUI_EVENT_KEY` | dispatcher | Normalised key name (`ctrl+q`, `wheel:down`). |
| `TUI_EVENT_X`, `TUI_EVENT_Y` | mouse | Pointer column / row (1-based). |
| `TUI_EVENT_PANE`, `TUI_EVENT_WIDGET` | dispatcher | Pane / widget under the pointer or focused. |
| `TUI_EVENT_BUTTON`, `TUI_EVENT_RAWBTN` | mouse | Button name / raw SGR button code. |
| `TUI_EVENT_COUNT` | dispatcher | Number of identical scroll events merged into this dispatch. |
| `TUI_EVENT_PASTE` | paste | Bracketed-paste text. |
| `TUI_PANE_ROWS`, `TUI_PANE_COLS` | `tui.pane_size` | Pane content size. |
| `TUI_SGR`, `TUI_FG`, `TUI_BG`, `TUI_MODS` | `tui.class.sgr`, `tui.style.sgr` | Resolved style. |
| `TUI_CLASSES` | `tui.class.names` | Sorted theme keys. |
| `TUI_SYS_*` | `tui.sys.*` | System samples. |
| `_TUI_FACTORY_LAST_ID`, `_TUI_FACTORY_GRID_CELLS` | `tui.factory.*` | Last generated ids (public by documented exception). |
