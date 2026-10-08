# Core: lifecycle, layout & runtime

The always-loaded core (`lib/tui.sh`, `lib/tui_api.sh`, `lib/state.sh`, `lib/markup/tui_factory.sh`): starting the app, building the pane tree, tabs, runtime (factory) widgets, output, background process streaming, live updates, getters, logging and the event/result variables everything else reads. ← [API index](README.md) for the full module list and a task-oriented tour with examples.

Each function has its own page; the summary tables link to them, and the full entries follow each table. Functions return `0` unless their entry says otherwise. Getters print to stdout, so call them in `$(...)`; the fork-free alternatives that set variables are noted on each entry.

## Lifecycle

`tui.start` is the usual entry point. `tui.init` + `tui.run` are the manual form for apps that build their UI in code.

<!-- api: tui.start tui.start_cached tui.init tui.run tui.stop tui.cleanup tui.require tui.tick.add tui.tick.remove tui.on_resize -->

| Function | Summary |
|---|---|
| [`tui.start`](core/tui.start.md) | Runs a markup-driven app: validates the page, initializes the terminal, loads `FILE` and runs the main loop until the app quits. |
| [`tui.start_cached`](core/tui.start_cached.md) | Like [`tui.start`](/api/core/tui.start.html), but first records every page the app can reach into the page cache, so later page switches replay instead of parsing. |
| [`tui.init`](core/tui.init.md) | Takes over the terminal and prepares an empty `root` pane. |
| [`tui.run`](core/tui.run.md) | Runs the main loop (input, dispatch, render, ticks) until [`tui.stop`](/api/core/tui.stop.html) is called, then restores the terminal. |
| [`tui.stop`](core/tui.stop.md) | Asks the main loop to exit after the current iteration. |
| [`tui.cleanup`](core/tui.cleanup.md) | Restores the terminal: mouse tracking and bracketed paste off, style reset, cursor shown, main screen, unread input drained, original `stty` settings back. |
| [`tui.require`](core/tui.require.md) | Sources an optional bundled library once per process. |
| [`tui.tick.add`](core/tui.tick.add.md) | Registers `FN` to run once per main-loop iteration. |
| [`tui.tick.remove`](core/tui.tick.remove.md) | Unregisters a tick listener. Unknown names are ignored. |
| [`tui.on_resize`](core/tui.on_resize.md) | Marks the terminal as resized; the main loop re-lays out on its next iteration. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.start.md %}

{% include_relative core/tui.start_cached.md %}

{% include_relative core/tui.init.md %}

{% include_relative core/tui.run.md %}

{% include_relative core/tui.stop.md %}

{% include_relative core/tui.cleanup.md %}

{% include_relative core/tui.require.md %}

{% include_relative core/tui.tick.add.md %}

{% include_relative core/tui.tick.remove.md %}

{% include_relative core/tui.on_resize.md %}

</div>

<!-- /api -->

## Layout (panes)

Panes form a tree rooted at `root`. Splits divide a pane among children by integer weight; leaves hold widgets or output. Pane names are used in bash variable names, so use letters, digits and `_` only.

<!-- api: tui.hsplit tui.vsplit tui.grid tui.fixed tui.pane_title tui.pane_border tui.pane_pad tui.pane_gap tui.pane_fuse tui.pane_divider tui.pane_divider_class tui.pane_title_pos tui.pane_title_align tui.pane_resizable tui.pane_handle tui.resize tui.resize.reset tui.collapse tui.collapsed tui.pane_align tui.pane_valign tui.pane_minsize tui.pane_maxsize tui.pane_scroll tui.pane_scroll_into_view tui.scroll.to tui.pane_strict_fit tui.pane_size tui.capture tui.content_area tui.pane.focus tui.relayout tui.clear_pane tui.render tui.redraw tui.frame.request -->

| Function | Summary |
|---|---|
| [`tui.hsplit`](core/tui.hsplit.md) | Splits `PARENT` into side-by-side child panes. |
| [`tui.vsplit`](core/tui.vsplit.md) | Splits `PARENT` into stacked child panes, top to bottom. |
| [`tui.grid`](core/tui.grid.md) | Lays `NAME...` out as a grid of cells inside `PARENT`, row by row. |
| [`tui.fixed`](core/tui.fixed.md) | Lays children out as fixed-size cells that flow left to right and wrap, like keys on a keyboard. |
| [`tui.pane_title`](core/tui.pane_title.md) | Sets the title drawn in the pane's top border. |
| [`tui.pane_border`](core/tui.pane_border.md) | Sets the border style of a pane. |
| [`tui.pane_pad`](core/tui.pane_pad.md) | Sets blank columns (`HPAD`) and rows (`VPAD`) on each side inside the pane. |
| [`tui.pane_gap`](core/tui.pane_gap.md) | Gets or sets the gap between children of a split pane. |
| [`tui.pane_fuse`](core/tui.pane_fuse.md) | Fuses a pane with its siblings so neighbouring borders share one line. |
| [`tui.pane_divider`](core/tui.pane_divider.md) | Sets the border style of the line a fused pane shares with its neighbour. |
| [`tui.pane_divider_class`](core/tui.pane_divider_class.md) | Sets the theme class that colours the line a fused pane shares with its neighbour. |
| [`tui.pane_title_pos`](core/tui.pane_title_pos.md) | Sets which border line carries a pane's title. |
| [`tui.pane_title_align`](core/tui.pane_title_align.md) | Sets where along its border line a pane's title sits. |
| [`tui.pane_resizable`](core/tui.pane_resizable.md) | Allows a pane to be resized on one or both axes, by mouse handle or keyboard. |
| [`tui.pane_handle`](core/tui.pane_handle.md) | Chooses the mouse handle that resizes a resizable pane. |
| [`tui.resize`](core/tui.resize.md) | Grows `PANE` by `DW` columns and `DH` rows (negative values shrink) with the same clamping as a drag. |
| [`tui.resize.reset`](core/tui.resize.reset.md) | Restores the split weights recorded before the first resize, for the split holding `PANE` and every split above it. |
| [`tui.collapse`](core/tui.collapse.md) | Collapses (`on`), expands (`off`) or toggles (default) a collapsible pane, then lays out again. |
| [`tui.collapsed`](core/tui.collapsed.md) | Reports whether a pane is collapsed. |
| [`tui.pane_align`](core/tui.pane_align.md) | Sets the default horizontal alignment for widgets in the pane. |
| [`tui.pane_valign`](core/tui.pane_valign.md) | Sets the default vertical anchor for widgets in the pane. Default: `top`. |
| [`tui.pane_minsize`](core/tui.pane_minsize.md) | Sets the smallest size at which the pane shows its content. Below it, the pane shows a `min space = WxH` notice instead. |
| [`tui.pane_maxsize`](core/tui.pane_maxsize.md) | Caps the size a split gives the pane. |
| [`tui.pane_scroll`](core/tui.pane_scroll.md) | Enables scrolling of the pane's output and resets its scroll position to the top left. |
| [`tui.pane_scroll_into_view`](core/tui.pane_scroll_into_view.md) | Sets whether focus scrolls a vertically scrolling pane to reveal the focused widget. Default: `true`. |
| [`tui.scroll.to`](core/tui.scroll.to.md) | Scrolls the pane that holds widget `TARGET` (or the pane `TARGET` itself) so the widget sits at the specified viewport position. |
| [`tui.pane_strict_fit`](core/tui.pane_strict_fit.md) | Turns the automatic content-fit check of a leaf pane on (default) or off. |
| [`tui.pane_size`](core/tui.pane_size.md) | Stores the usable content size of a pane (inside border and padding) in variables, without a subshell. |
| [`tui.capture`](core/tui.capture.md) | Runs `CMD` and stores its standard output in `VAR`, like `VAR="$(CMD ARGS...)"` but without a subshell. |
| [`tui.content_area`](core/tui.content_area.md) | Prints the content rectangle of a pane as `ROW COL HEIGHT WIDTH` (1-based, inside border and padding). |
| [`tui.pane.focus`](core/tui.pane.focus.md) | Makes `PANE` the keyboard pane: the target of scroll keys, drawn with a highlighted border. |
| [`tui.relayout`](core/tui.relayout.md) | Recomputes geometry and repaints in one synchronized frame. Use it after changing borders, padding, titles or splits while the app runs. |
| [`tui.clear_pane`](core/tui.clear_pane.md) | Blanks the pane's content rectangle on screen. |
| [`tui.render`](core/tui.render.md) | Repaints every pane, widget and output now, as one buffered frame. |
| [`tui.redraw`](core/tui.redraw.md) | Same as [`tui.render`](/api/core/tui.render.html). |
| [`tui.frame.request`](core/tui.frame.request.md) | Asks for a relayout and repaint at the end of the current input-loop iteration. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.hsplit.md %}

{% include_relative core/tui.vsplit.md %}

{% include_relative core/tui.grid.md %}

{% include_relative core/tui.fixed.md %}

{% include_relative core/tui.pane_title.md %}

{% include_relative core/tui.pane_border.md %}

{% include_relative core/tui.pane_pad.md %}

{% include_relative core/tui.pane_gap.md %}

{% include_relative core/tui.pane_fuse.md %}

{% include_relative core/tui.pane_divider.md %}

{% include_relative core/tui.pane_divider_class.md %}

{% include_relative core/tui.pane_title_pos.md %}

{% include_relative core/tui.pane_title_align.md %}

{% include_relative core/tui.pane_resizable.md %}

{% include_relative core/tui.pane_handle.md %}

{% include_relative core/tui.resize.md %}

{% include_relative core/tui.resize.reset.md %}

{% include_relative core/tui.collapse.md %}

{% include_relative core/tui.collapsed.md %}

{% include_relative core/tui.pane_align.md %}

{% include_relative core/tui.pane_valign.md %}

{% include_relative core/tui.pane_minsize.md %}

{% include_relative core/tui.pane_maxsize.md %}

{% include_relative core/tui.pane_scroll.md %}

{% include_relative core/tui.pane_scroll_into_view.md %}

{% include_relative core/tui.scroll.to.md %}

{% include_relative core/tui.pane_strict_fit.md %}

{% include_relative core/tui.pane_size.md %}

{% include_relative core/tui.capture.md %}

{% include_relative core/tui.content_area.md %}

{% include_relative core/tui.pane.focus.md %}

{% include_relative core/tui.relayout.md %}

{% include_relative core/tui.clear_pane.md %}

{% include_relative core/tui.render.md %}

{% include_relative core/tui.redraw.md %}

{% include_relative core/tui.frame.request.md %}

</div>

<!-- /api -->

## Page state

A page can keep state while the user visits other pages. In markup: `keep_value="true"` on a widget (value, cursor, scroll, selection), `keep_collapsed="true"` and `keep_size="true"` on a pane, or `keep_state="true"` on `<tui>` for every widget and pane of the page. `persist="session"` (the default) keeps it for this run; `persist="disk"` (on a widget, a pane or `<tui>`) implies the keeping and also writes the fields to `$TUI_HOME/state/store`, so they are back the next time the app starts. State is saved when the page is left and restored after it is built again, also after `tui.page.refresh` rebuilt panes. The store is `_TUI_STORE["PAGE|ID|FIELD"]`.

The disk file is data only (`# dabt-state 1`, then one escaped `PAGE TAB ID TAB FIELD TAB VALUE` line per entry; fields `value cursor scroll sel collapsed size focus`). It is read with `read -r` and never sourced, so `TUI_HOME` is not a code-execution boundary; lines that do not parse are skipped. It is loaded on first use, written when a page is left or the app exits (only if something changed) and by `tui.store.flush`. `tui.page.reset`, `tui.page.reset_field` and `tui.page.reset_all` also remove the matching disk entries.

Focus can be kept too. `keep_focus="true"` on a widget: when it has the focus as a page is left and the next page has a widget with the same id, focus lands on it before the first render (and a keep_focus widget is focused again when you return to its page). `<tui focus_on_enter="ID|keep|first">` sets where focus lands on entry: `first` (the default), `keep` (the id focused when the page was last left, kept in the store as field `focus`) or the id of a widget; an id that does not exist falls back to `first`.

<!-- api: tui.store.set tui.store.get tui.store.unset tui.store.has tui.store.register_type tui.page.reset tui.page.reset_field tui.page.reset_all tui.page.resettable tui.store.flush tui.store.file -->

| Function | Summary |
|---|---|
| [`tui.store.set`](core/tui.store.set.md) | Stores one field of a widget or pane in the page-state store. |
| [`tui.store.get`](core/tui.store.get.md) | Reads one stored field into `REPLY`. |
| [`tui.store.unset`](core/tui.store.unset.md) | Drops stored state: one field, every field of one id, or a whole page. |
| [`tui.store.has`](core/tui.store.has.md) | Reports whether anything is stored for a page, or for one id. |
| [`tui.store.register_type`](core/tui.store.register_type.md) | Sets which fields a widget type keeps. |
| [`tui.page.reset`](core/tui.page.reset.md) | Forgets the stored state of a page and puts the current page back to its first-build state. |
| [`tui.page.reset_field`](core/tui.page.reset_field.md) | Puts one kept widget or pane back to its first-build state. |
| [`tui.page.reset_all`](core/tui.page.reset_all.md) | Empties the whole store (every page) and resets the current page. |
| [`tui.page.resettable`](core/tui.page.resettable.md) | Reports whether a reset would change anything on the current page. |
| [`tui.store.flush`](core/tui.store.flush.md) | Writes the disk image of the page-state store to `tui.store.file` now. |
| [`tui.store.file`](core/tui.store.file.md) | Prints the path of the file that holds the `persist="disk"` page state: `$TUI_HOME/state/store`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.store.set.md %}

{% include_relative core/tui.store.get.md %}

{% include_relative core/tui.store.unset.md %}

{% include_relative core/tui.store.has.md %}

{% include_relative core/tui.store.register_type.md %}

{% include_relative core/tui.page.reset.md %}

{% include_relative core/tui.page.reset_field.md %}

{% include_relative core/tui.page.reset_all.md %}

{% include_relative core/tui.page.resettable.md %}

{% include_relative core/tui.store.flush.md %}

{% include_relative core/tui.store.file.md %}

</div>

<!-- /api -->

## Tabs

A tab group is a header pane with one button per tab and a content pane that the active tab's action fills. In markup: `<tabs>`, see [../guide/grid-layouts-and-tabs.md](../guide/grid-layouts-and-tabs.md).

<!-- api: tui.tabs.add tui.tabs.compact tui.tabs.build tui.tabs.activate -->

| Function | Summary |
|---|---|
| [`tui.tabs.add`](core/tui.tabs.add.md) | Registers one tab before the group is built. |
| [`tui.tabs.compact`](core/tui.tabs.compact.md) | Picks the header style of a tab group. Call it before [`tui.tabs.build`](/api/core/tui.tabs.build.html). |
| [`tui.tabs.build`](core/tui.tabs.build.md) | Builds the header row for registered tabs and activates the default tab (or the first). |
| [`tui.tabs.activate`](core/tui.tabs.activate.md) | Makes a tab active: focuses its header button and calls its action as `ACTION TAB_ID`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.tabs.add.md %}

{% include_relative core/tui.tabs.compact.md %}

{% include_relative core/tui.tabs.build.md %}

{% include_relative core/tui.tabs.activate.md %}

</div>

<!-- /api -->

## Factory (runtime widgets)

Constructors for layouts whose shape is only known at runtime. Ids are generated and tracked per namespace, so one call tears everything down again.

<!-- api: tui.factory.label tui.factory.button tui.factory.input tui.factory.checkbox tui.factory.grid tui.factory.clear -->

| Function | Summary |
|---|---|
| [`tui.factory.label`](core/tui.factory.label.md) | Creates a label with a generated id, tracked under namespace `NS`. |
| [`tui.factory.button`](core/tui.factory.button.md) | Creates a button with a generated id, tracked under namespace `NS`. `ACTION` is called as `ACTION ID`. |
| [`tui.factory.input`](core/tui.factory.input.md) | Creates a single-line input with a generated id, tracked under namespace `NS`. |
| [`tui.factory.checkbox`](core/tui.factory.checkbox.md) | Creates a checkbox with a generated id, tracked under namespace `NS`. |
| [`tui.factory.grid`](core/tui.factory.grid.md) | Builds a grid of `COUNT` cells with generated pane ids, for layouts whose size is only known at runtime. |
| [`tui.factory.clear`](core/tui.factory.clear.md) | Removes every widget and pane created under namespace `NS` and turns its grid parents back into empty leaf panes. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.factory.label.md %}

{% include_relative core/tui.factory.button.md %}

{% include_relative core/tui.factory.input.md %}

{% include_relative core/tui.factory.checkbox.md %}

{% include_relative core/tui.factory.grid.md %}

{% include_relative core/tui.factory.clear.md %}

</div>

<!-- /api -->

## Content and output

Text content of leaf panes. Repaints are queued and coalesced, so several updates in one callback cost one frame.

<!-- api: tui.output tui.output_append tui.output_clear tui.set_text tui.set_canvas tui.canvas.source tui.canvas.fresh tui.canvas.patch -->

| Function | Summary |
|---|---|
| [`tui.output`](core/tui.output.md) | Replaces the pane's content with text, or with stdin when no `TEXT` is given. |
| [`tui.output_append`](core/tui.output_append.md) | Appends lines to the pane's content, from arguments or stdin. |
| [`tui.output_clear`](core/tui.output_clear.md) | Empties the pane's content and repaints the pane immediately. |
| [`tui.set_text`](core/tui.set_text.md) | Replaces the pane's content like [`tui.output`](/api/core/tui.output.html), but skips the work when `TEXT` equals what it set last time. |
| [`tui.set_canvas`](core/tui.set_canvas.md) | Sets the pane's content to a ready-made frame: one line per row, each already as wide as the pane's content area. The pane draws the lines as they are, in its own style. |
| [`tui.canvas.source`](core/tui.canvas.source.md) | Names the function that keeps the frame of a canvas pane, for an animation that draws changes with [`tui.canvas.patch`](/api/core/tui.canvas.patch.html) instead of sending the whole frame. |
| [`tui.canvas.fresh`](core/tui.canvas.fresh.md) | Returns `0` while the last canvas frame (or patch) is still what the screen shows, because nothing else has painted since. Returns `1` otherwise. |
| [`tui.canvas.patch`](core/tui.canvas.patch.md) | Draws `BYTES` over the canvas at once, in one flush: absolute cursor moves and cells, for example only the cells an animation changed. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.output.md %}

{% include_relative core/tui.output_append.md %}

{% include_relative core/tui.output_clear.md %}

{% include_relative core/tui.set_text.md %}

{% include_relative core/tui.set_canvas.md %}

{% include_relative core/tui.canvas.source.md %}

{% include_relative core/tui.canvas.fresh.md %}

{% include_relative core/tui.canvas.patch.md %}

</div>

<!-- /api -->

## Background painters

Painters run in background processes and draw directly to the terminal with absolute cursor moves, so their frames cost the main loop nothing and a hover or focus highlight is never queued behind them. A painter receives updates from the main loop through small state files and sleeps without forking.

<!-- api: tui.async.start tui.async.stop tui.async.stop_all tui.async.active tui.async.put tui.async.get tui.async.wait tui.async.emit tui.async.covered -->

| Function | Summary |
|---|---|
| [`tui.async.start`](core/tui.async.start.md) | Forks FN with ARG... into the background as a painter: a function running in its own process that paints directly to the terminal with absolute cursor moves, so its frames cost the main loop nothing. |
| [`tui.async.stop`](core/tui.async.stop.md) | Ends the painter named NAME, if it exists. |
| [`tui.async.stop_all`](core/tui.async.stop_all.md) | Ends every painter and removes the state directory. |
| [`tui.async.active`](core/tui.async.active.md) | Returns 0 while a painter is running; 1 when none are running, or when NAME is given and that painter is not running. |
| [`tui.async.put`](core/tui.async.put.md) | The main loop's way to send a small value to a painter: writes VALUE to a temporary file that the painter can read with [`tui.async.get`](/api/core/tui.async.get.html). |
| [`tui.async.get`](core/tui.async.get.md) | Inside a painter: reads a value sent by the main loop via [`tui.async.put`](/api/core/tui.async.put.html) into VAR. |
| [`tui.async.wait`](core/tui.async.wait.md) | Inside a painter: sleeps without forking, by waiting on a pipe that is held open and never written. Returns immediately after the timeout, or when the main process exits. |
| [`tui.async.emit`](core/tui.async.emit.md) | Inside a painter: sends FRAME to the terminal. A painter's stdout is closed, so this is the only way it draws. |
| [`tui.async.covered`](core/tui.async.covered.md) | Inside a painter: returns 0 while something is open over the page (a modal, the command palette, a dialog, or a layer); 1 when the page is fully visible. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.async.start.md %}

{% include_relative core/tui.async.stop.md %}

{% include_relative core/tui.async.stop_all.md %}

{% include_relative core/tui.async.active.md %}

{% include_relative core/tui.async.put.md %}

{% include_relative core/tui.async.get.md %}

{% include_relative core/tui.async.wait.md %}

{% include_relative core/tui.async.emit.md %}

{% include_relative core/tui.async.covered.md %}

</div>

<!-- /api -->

## Process streaming (`tui.exec`)

<!-- api: tui.exec tui.exec.cancel_pane -->

| Function | Summary |
|---|---|
| [`tui.exec`](core/tui.exec.md) | Runs a shell command in a pseudo-terminal and streams its output into a pane while the UI stays responsive. |
| [`tui.exec.cancel_pane`](core/tui.exec.cancel_pane.md) | Kills and dismisses every `tui.exec` instance targeting `PANE`, running or finished, and empties the pane. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.exec.md %}

{% include_relative core/tui.exec.cancel_pane.md %}

</div>

<!-- /api -->

## Live updates

Timers, clocks, watches and the system samplers share one tick listener, cost no fork per update, and are cleared on page change and exit.

<!-- api: tui.every tui.after tui.every.cancel tui.every.pause tui.every.resume tui.every.clear tui.every.list tui.clock tui.watch tui.watch.stop tui.watch.now tui.monitor tui.sys.cpu tui.sys.mem tui.sys.load tui.sys.uptime tui.hist.push tui.hist.get -->

| Function | Summary |
|---|---|
| [`tui.every`](core/tui.every.md) | Calls `FN` repeatedly on a timer from the main loop. |
| [`tui.after`](core/tui.after.md) | Calls `FN ID` once, `SEC` seconds from now. |
| [`tui.every.cancel`](core/tui.every.cancel.md) | Removes a timer created by [`tui.every`](/api/core/tui.every.html), [`tui.after`](/api/core/tui.after.html), [`tui.clock`](/api/core/tui.clock.html) or [`tui.monitor`](/api/core/tui.monitor.html). Unknown ids are ignored. |
| [`tui.every.pause`](core/tui.every.pause.md) | Stops a timer from firing until [`tui.every.resume`](/api/core/tui.every.resume.html) is called. |
| [`tui.every.resume`](core/tui.every.resume.md) | Resumes a paused timer. It fires on the next loop iteration, then at its normal interval. |
| [`tui.every.clear`](core/tui.every.clear.md) | Removes every timer, including clocks and monitors. Watches from [`tui.watch`](/api/core/tui.watch.html) keep running. |
| [`tui.every.list`](core/tui.every.list.md) | Prints one line per timer. |
| [`tui.clock`](core/tui.clock.md) | Shows a live clock in a pane, updated on every whole second. |
| [`tui.watch`](core/tui.watch.md) | Runs a shell command every `SEC` seconds in the background and shows its latest output in a pane, like `watch`. |
| [`tui.watch.stop`](core/tui.watch.stop.md) | Stops a watch and kills its background process. Unknown ids are ignored. |
| [`tui.watch.now`](core/tui.watch.now.md) | Restarts a watch so its command runs again right away. |
| [`tui.monitor`](core/tui.monitor.md) | Shows a ready-made system dashboard in a pane: CPU, memory and swap gauges, a CPU history sparkline, memory in MB, load average and uptime. |
| [`tui.sys.cpu`](core/tui.sys.cpu.md) | Samples CPU usage since the previous call, fork-free. |
| [`tui.sys.mem`](core/tui.sys.mem.md) | Samples memory and swap usage from `/proc/meminfo`, fork-free. |
| [`tui.sys.load`](core/tui.sys.load.md) | Reads the load averages from `/proc/loadavg`. |
| [`tui.sys.uptime`](core/tui.sys.uptime.md) | Reads the system uptime from `/proc/uptime`. |
| [`tui.hist.push`](core/tui.hist.push.md) | Appends a value to a named rolling series, dropping the oldest beyond `MAX`. |
| [`tui.hist.get`](core/tui.hist.get.md) | Prints a series, oldest first. With `VAR` the series is stored in that variable instead, which costs no subshell. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.every.md %}

{% include_relative core/tui.after.md %}

{% include_relative core/tui.every.cancel.md %}

{% include_relative core/tui.every.pause.md %}

{% include_relative core/tui.every.resume.md %}

{% include_relative core/tui.every.clear.md %}

{% include_relative core/tui.every.list.md %}

{% include_relative core/tui.clock.md %}

{% include_relative core/tui.watch.md %}

{% include_relative core/tui.watch.stop.md %}

{% include_relative core/tui.watch.now.md %}

{% include_relative core/tui.monitor.md %}

{% include_relative core/tui.sys.cpu.md %}

{% include_relative core/tui.sys.mem.md %}

{% include_relative core/tui.sys.load.md %}

{% include_relative core/tui.sys.uptime.md %}

{% include_relative core/tui.hist.push.md %}

{% include_relative core/tui.hist.get.md %}

</div>

<!-- /api -->

## Getters

Read-only. Pane getters return `1` for an unknown pane.

<!-- api: tui.get.dimensions tui.get.terminal tui.get.position tui.get.rect tui.get.content_area tui.get.border tui.get.title tui.get.pad tui.get.split tui.get.children tui.get.parent tui.get.panes tui.get.lines tui.get.scroll tui.get.style tui.get.widgets tui.get.type tui.get.pane tui.get.action tui.get.checked tui.get.focused tui.get.hovered tui.get.pane_focus tui.get.page tui.get.pages tui.get.event tui.get.classes tui.get.class.style -->

| Function | Summary |
|---|---|
| [`tui.get.dimensions`](core/tui.get.dimensions.md) | Prints the size of the terminal or of a pane. |
| [`tui.get.terminal`](core/tui.get.terminal.md) | Prints the terminal size as `ROWS COLS`. |
| [`tui.get.position`](core/tui.get.position.md) | Prints the top-left corner of a pane as `ROW COL` (1-based). Returns `1` for an unknown pane. |
| [`tui.get.rect`](core/tui.get.rect.md) | Prints the outer rectangle of a pane as `ROW COL HEIGHT WIDTH`. Returns `1` for an unknown pane. |
| [`tui.get.content_area`](core/tui.get.content_area.md) | Prints the usable rectangle inside border and padding as `ROW COL HEIGHT WIDTH`. Returns `1` for an unknown pane. |
| [`tui.get.border`](core/tui.get.border.md) | Prints the border actually drawn: `single`, `double`, `heavy` or `none`. Returns `1` for an unknown pane. |
| [`tui.get.title`](core/tui.get.title.md) | Prints the pane title (empty when none). Returns `1` for an unknown pane. |
| [`tui.get.pad`](core/tui.get.pad.md) | Prints the pane padding as `HPAD VPAD`. Returns `1` for an unknown pane. |
| [`tui.get.split`](core/tui.get.split.md) | Prints how a pane is split: `h`, `v`, `f` (fixed) or empty for a leaf. Returns `1` for an unknown pane. |
| [`tui.get.children`](core/tui.get.children.md) | Prints the child pane ids on one line, space-separated (empty for a leaf). Returns `1` for an unknown pane. |
| [`tui.get.parent`](core/tui.get.parent.md) | Prints the id of the pane that contains `PANE`. Returns `1` for `root` or an unknown pane. |
| [`tui.get.panes`](core/tui.get.panes.md) | Prints every pane id, one per line; with `leaves`, only panes without children. |
| [`tui.get.lines`](core/tui.get.lines.md) | Prints the number of output lines a pane holds (`0` for none or an unknown pane). |
| [`tui.get.scroll`](core/tui.get.scroll.md) | Prints the scroll state as `MODE V_OFFSET H_OFFSET LINES MAX_WIDTH`, e.g. `v 12 0 240 80`. Returns `1` for an unknown pane. |
| [`tui.get.style`](core/tui.get.style.md) | Prints one resolved style field of a pane or widget. |
| [`tui.get.widgets`](core/tui.get.widgets.md) | Prints widget ids in draw order, one per line: all of them, or only those in `PANE`. |
| [`tui.get.type`](core/tui.get.type.md) | Prints the widget type: `label`, `button`, `input`, `checkbox`, `password`, `textarea`, `list`, `table`, `select` or `progress`. Returns `1` for an unknown id. |
| [`tui.get.pane`](core/tui.get.pane.md) | Prints the pane a widget lives in. Returns `1` for an unknown id. |
| [`tui.get.action`](core/tui.get.action.md) | Prints the action function of a widget (empty when none or unknown). |
| [`tui.get.checked`](core/tui.get.checked.md) | Prints nothing; returns `0` when `ID` is a checked checkbox, else `1`. |
| [`tui.get.focused`](core/tui.get.focused.md) | Prints the id of the focused widget (empty when none). |
| [`tui.get.hovered`](core/tui.get.hovered.md) | Prints the id of the widget (default) or pane under the mouse pointer (empty when none). |
| [`tui.get.pane_focus`](core/tui.get.pane_focus.md) | Prints the keyboard pane: the scroll target with the highlighted border (empty when none). |
| [`tui.get.page`](core/tui.get.page.md) | Prints the absolute path of the current page file (empty before a page is loaded). |
| [`tui.get.pages`](core/tui.get.pages.md) | Prints the pages linked by a `<button page="…">` so far, sorted, one per line as `PAGE<TAB>TITLE`. |
| [`tui.get.event`](core/tui.get.event.md) | Prints the current input event on one line: `type=… key=… x=… y=… pane=… widget=… button=…`. |
| [`tui.get.classes`](core/tui.get.classes.md) | Prints every key the loaded theme defines, sorted, one per line. |
| [`tui.get.class.style`](core/tui.get.class.style.md) | Prints one field of a theme class, without a pane or widget. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.get.dimensions.md %}

{% include_relative core/tui.get.terminal.md %}

{% include_relative core/tui.get.position.md %}

{% include_relative core/tui.get.rect.md %}

{% include_relative core/tui.get.content_area.md %}

{% include_relative core/tui.get.border.md %}

{% include_relative core/tui.get.title.md %}

{% include_relative core/tui.get.pad.md %}

{% include_relative core/tui.get.split.md %}

{% include_relative core/tui.get.children.md %}

{% include_relative core/tui.get.parent.md %}

{% include_relative core/tui.get.panes.md %}

{% include_relative core/tui.get.lines.md %}

{% include_relative core/tui.get.scroll.md %}

{% include_relative core/tui.get.style.md %}

{% include_relative core/tui.get.widgets.md %}

{% include_relative core/tui.get.type.md %}

{% include_relative core/tui.get.pane.md %}

{% include_relative core/tui.get.action.md %}

{% include_relative core/tui.get.checked.md %}

{% include_relative core/tui.get.focused.md %}

{% include_relative core/tui.get.hovered.md %}

{% include_relative core/tui.get.pane_focus.md %}

{% include_relative core/tui.get.page.md %}

{% include_relative core/tui.get.pages.md %}

{% include_relative core/tui.get.event.md %}

{% include_relative core/tui.get.classes.md %}

{% include_relative core/tui.get.class.style.md %}

</div>

<!-- /api -->

## Logging and perf

<!-- api: tui.log tui.log.debug tui.log.info tui.log.warn tui.log.error tui.log.file tui.perf.mean_render_ms tui.perf.report tui.perf.reset -->

| Function | Summary |
|---|---|
| [`tui.log`](core/tui.log.md) | Appends a line to the app's log file. stdout is the screen, so logs go to a file. |
| [`tui.log.debug`](core/tui.log.debug.md) | Same as `tui.log MSG debug`. See [`tui.log`](/api/core/tui.log.html). |
| [`tui.log.info`](core/tui.log.info.md) | Same as `tui.log MSG info`. See [`tui.log`](/api/core/tui.log.html). |
| [`tui.log.warn`](core/tui.log.warn.md) | Same as `tui.log MSG warn`. See [`tui.log`](/api/core/tui.log.html). |
| [`tui.log.error`](core/tui.log.error.md) | Same as `tui.log MSG error`. See [`tui.log`](/api/core/tui.log.html). |
| [`tui.log.file`](core/tui.log.file.md) | Prints the path [`tui.log`](/api/core/tui.log.html) writes to today. |
| [`tui.perf.mean_render_ms`](core/tui.perf.mean_render_ms.md) | Prints the mean frame render time in milliseconds over the last `SECONDS`. |
| [`tui.perf.report`](core/tui.perf.report.md) | Prints one line per tracked span (`span<TAB>name<TAB>mean_us<TAB>p95_us<TAB>count`) and one line per counter (`counter<TAB>name<TAB>total`). |
| [`tui.perf.reset`](core/tui.perf.reset.md) | Clears every tracked span and counter. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.log.md %}

{% include_relative core/tui.log.debug.md %}

{% include_relative core/tui.log.info.md %}

{% include_relative core/tui.log.warn.md %}

{% include_relative core/tui.log.error.md %}

{% include_relative core/tui.log.file.md %}

{% include_relative core/tui.perf.mean_render_ms.md %}

{% include_relative core/tui.perf.report.md %}

{% include_relative core/tui.perf.reset.md %}

</div>

<!-- /api -->

## Background work

Work that takes noticeable time runs in a separate process, so the interface stays responsive; a spinner tells the user something is happening, and the result is shown only once it is complete. Changing a page that is already on screen (addons, generated content) does not go through a process at all: [`tui.page.refresh`](core/tui.page.refresh.md) rebuilds just the panes that changed, within the budget of a page switch.

<!-- api: tui.job.run tui.job.cancel tui.job.running tui.page.refresh tui.page.rebuild -->

| Function | Summary |
|---|---|
| [`tui.job.run`](core/tui.job.run.md) | Runs `WORKFN ARG...` in the background and keeps the interface running. When it has finished, `DONEFN ID RC OUTFILE` is called in the main shell. If the work is still going after `MS` milliseconds, a spinner with `TEXT` shows in the top-right corner of the frame, so the user can see that something is happening. |
| [`tui.job.cancel`](core/tui.job.cancel.md) | Stops the background job `ID` started with [`tui.job.run`](/api/core/tui.job.run.html). Its `DONEFN` is not called, its files are removed, and the spinner goes away if it was the last job. |
| [`tui.job.running`](core/tui.job.running.md) | Tells whether the background job `ID` is still pending, that is started with [`tui.job.run`](/api/core/tui.job.run.html) and its `DONEFN` not yet called. |
| [`tui.page.refresh`](core/tui.page.refresh.md) | Re-applies the [addons](/guide/markup.html#addons) on disk (and re-runs templates and loops) on the page that is on screen, and rebuilds only the panes whose content changed. A page switch has 100 ms; so does this. |
| [`tui.page.rebuild`](core/tui.page.rebuild.md) | Builds the page `FILE` again in the background and shows it when it is complete. The options are those of [`tui.job.run`](/api/core/tui.job.run.html), which runs it. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.job.run.md %}

{% include_relative core/tui.job.cancel.md %}

{% include_relative core/tui.job.running.md %}

{% include_relative core/tui.page.refresh.md %}

{% include_relative core/tui.page.rebuild.md %}

</div>

<!-- /api -->

## Registry

<!-- api: tui.register tui.registered tui.register.style_contract tui.addon.dir tui.addon.undir tui.cache.forget -->

| Function | Summary |
|---|---|
| [`tui.register`](core/tui.register.md) | Registers one or more handlers `FN` for `NAME` under `KIND`. |
| [`tui.registered`](core/tui.registered.md) | Looks up `NAME`'s handlers under `KIND` into `$_TUI_REGISTERED` (space-joined, registration order). |
| [`tui.register.style_contract`](core/tui.register.style_contract.md) | Registers `NAME`'s style contract (registry kind `style`): the pseudo-states it can enter and the framework classes it draws with, e.g. `"states:hover focus"` `"classes:.list_sel"`. |
| [`tui.addon.dir`](core/tui.addon.dir.md) | Adds a directory whose `*.xml` files hold [addons](/guide/markup.html#addons), so a plugin can ship its own page changes. The app's own `TUI_APP_CONF/addons` is always read. |
| [`tui.addon.undir`](core/tui.addon.undir.md) | Forgets a folder that was registered with [`tui.addon.dir`](/api/core/tui.addon.dir.html). Its addons stop applying to pages loaded from now on. |
| [`tui.cache.forget`](core/tui.cache.forget.md) | Drops everything cached for the page `FILE`, so its next visit builds it fresh. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative core/tui.register.md %}

{% include_relative core/tui.registered.md %}

{% include_relative core/tui.register.style_contract.md %}

{% include_relative core/tui.addon.dir.md %}

{% include_relative core/tui.addon.undir.md %}

{% include_relative core/tui.cache.forget.md %}

</div>

<!-- /api -->

## Event and result variables

| Variable | Set by | Meaning |
|---|---|---|
| `TUI_EVENT_TYPE` | dispatcher | `key`, `mouse` (wheel and drag included), `paste`. |
| `TUI_EVENT_KEY` | dispatcher | Normalised key name (`ctrl+q`, `wheel:down`). |
| `TUI_EVENT_X`, `TUI_EVENT_Y` | mouse | Pointer column / row (1-based). |
| `TUI_EVENT_PANE`, `TUI_EVENT_WIDGET` | dispatcher | Pane / widget under the pointer or focused. |
| `TUI_EVENT_ZONE`, `TUI_EVENT_ZONE_ID`, `TUI_EVENT_ZONE_ARG` | dispatcher | Mouse events: kind, id and argument of the topmost hit zone under the pointer (`scrollbar` + pane + `v`/`h`, `widget`/`hitbox` + widget id, `divider`, `handle`, `chevron`, `title`), empty over plain pane area. |
| `TUI_EVENT_BUTTON`, `TUI_EVENT_RAWBTN` | mouse | Button name / raw SGR button code. |
| `TUI_EVENT_COUNT` | dispatcher | Number of identical scroll events merged into this dispatch. |
| `TUI_EVENT_PASTE` | paste | Bracketed-paste text. |
| `TUI_PANE_ROWS`, `TUI_PANE_COLS` | [`tui.pane_size`](core/tui.pane_size.md) | Pane content size. |
| `TUI_SGR`, `TUI_FG`, `TUI_BG`, `TUI_MODS` | [`tui.class.sgr`](style/tui.class.sgr.md), [`tui.style.sgr`](style/tui.style.sgr.md) | Resolved style. |
| `TUI_CLASSES` | [`tui.class.names`](style/tui.class.names.md) | Sorted theme keys. |
| `TUI_SYS_*` | `tui.sys.*` | System samples. |
| `_TUI_FACTORY_LAST_ID`, `_TUI_FACTORY_GRID_CELLS` | `tui.factory.*` | Last generated ids (public by documented exception). |

Settings read when `tui.sh` is sourced: `TUI_APP_NAME` (config folder and log name, default `dabt`), `TUI_HOME`, `TUI_LOG_DIR`, `TUI_CONFIG_FILE`, `TUI_VALIDATE=0` (skip page validation), `TUI_IGNORE_INVALID_XML=1` (start despite validation errors).
