# Core: lifecycle, layout & runtime

The always-loaded core (`lib/tui.sh`, `lib/tui_api.sh`, `lib/state.sh`): starting the app, building the pane tree, tabs, runtime (factory) widgets, output, background process streaming, live updates, getters, logging/perf and the event/result variables everything else reads. ← [API index](README.md) for the full module list and a task-oriented tour with examples.

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

## Logging and perf

| Function | Parameters | Description |
|---|---|---|
| `tui.log` | `MSG [LEVEL]` | Append to `.tui_exec.log` (stdout is the screen, so logs go to a file). |
| `tui.log.debug` / `tui.log.info` / `tui.log.warn` / `tui.log.error` | `MSG` | Level shortcuts. |
| `tui.perf.mean_render_ms` | `SECONDS` | Mean frame time over the trailing window (needs `_TUI_PERF_TRACKING=1`; empty if no data). |

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
