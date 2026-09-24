# Input: keys, mouse & actions

`lib/input/tui_input.sh` - key/mouse binding tables, dispatch, defaults, pass-through, and the built-in actions bindable from `tui.bind`, `<bind action="…">`, `<button action="…">` or `tui.cmd.add`. Guide: [../guide/input-bindings.md](../guide/input-bindings.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

Every key and mouse event is decoded into a name (`ctrl+s`, `pgdn`, `wheel:up`, `mouse:right`, `paste`) and looked up in three tables: user bindings (`--user`, saved per app), code bindings (your app and markup), and the defaults from `share/defaults/keybinds.xml`, grouped so whole groups can be switched off. Handlers read the event from the `TUI_EVENT_*` variables ([Core](core.md#event-and-result-variables)). Functions return `0` unless their entry says otherwise.

## Input and bindings

<!-- api: tui.bind tui.unbind tui.bind.reset tui.bind.list tui.bind.table tui.bind.defaults tui.defaults.off tui.defaults.on tui.defaults.list -->
| Function | Summary |
|---|---|
| [`tui.bind`](input/tui.bind.md) | Binds a key or mouse event to a command. |
| [`tui.unbind`](input/tui.unbind.md) | Removes a code binding, or with `--user` a user binding. The default for `KEY` applies again. |
| [`tui.bind.reset`](input/tui.bind.reset.md) | Removes every code binding, or with `--user` every user binding. Defaults are not affected. |
| [`tui.bind.list`](input/tui.bind.list.md) | Prints every binding: user, then code, then defaults. |
| [`tui.bind.table`](input/tui.bind.table.md) | Builds the same rows as [`tui.bind.list`](/api/input/tui.bind.list.html) as an aligned, framed text table in the variable `_TBL`. |
| [`tui.bind.defaults`](input/tui.bind.defaults.md) | Reloads the default bindings, replacing the current defaults. |
| [`tui.defaults.off`](input/tui.defaults.off.md) | Switches groups of default bindings off. |
| [`tui.defaults.on`](input/tui.defaults.on.md) | Switches default groups back on, both the app-wide and the page-only setting. |
| [`tui.defaults.list`](input/tui.defaults.list.md) | Prints each default group, sorted, as `GROUP<TAB>on\|off<TAB>KEYS`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative input/tui.bind.md %}

{% include_relative input/tui.unbind.md %}

{% include_relative input/tui.bind.reset.md %}

{% include_relative input/tui.bind.list.md %}

{% include_relative input/tui.bind.table.md %}

{% include_relative input/tui.bind.defaults.md %}

{% include_relative input/tui.defaults.off.md %}

{% include_relative input/tui.defaults.on.md %}

{% include_relative input/tui.defaults.list.md %}

</div>
<!-- /api -->

## Saved user bindings

<!-- api: tui.bind.save tui.bind.load tui.bind.discard tui.bind.dirty tui.bind.saved_file -->
| Function | Summary |
|---|---|
| [`tui.bind.save`](input/tui.bind.save.md) | Writes the user bindings (`--user`) to disk; they load automatically on the next start. |
| [`tui.bind.load`](input/tui.bind.load.md) | Replaces the user bindings with those in `FILE` (default: the saved file) and marks them saved. |
| [`tui.bind.discard`](input/tui.bind.discard.md) | Drops unsaved changes to the user bindings by reloading the saved file. |
| [`tui.bind.dirty`](input/tui.bind.dirty.md) | Returns `0` while the user bindings differ from the saved file, else `1`. |
| [`tui.bind.saved_file`](input/tui.bind.saved_file.md) | Prints the path of the saved user bindings (`TUI_USER_KEYBINDS`). |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative input/tui.bind.save.md %}

{% include_relative input/tui.bind.load.md %}

{% include_relative input/tui.bind.discard.md %}

{% include_relative input/tui.bind.dirty.md %}

{% include_relative input/tui.bind.saved_file.md %}

</div>
<!-- /api -->

## Kill switch, terminal mode, clipboard

<!-- api: tui.keys.suspend tui.keys.suspend_key tui.keys.suspended tui.passthrough tui.passthrough.key tui.passthrough.active tui.clipboard.copy tui.clipboard.paste -->
| Function | Summary |
|---|---|
| [`tui.keys.suspend`](input/tui.keys.suspend.md) | Kill switch: turns every keyboard binding off, user and default, and shows a warning box. Default: `toggle`. |
| [`tui.keys.suspend_key`](input/tui.keys.suspend_key.md) | Changes the chord that toggles the keyboard kill switch. Default: `ctrl+alt+k`. |
| [`tui.keys.suspended`](input/tui.keys.suspended.md) | Returns `0` while the keyboard kill switch is on. |
| [`tui.passthrough`](input/tui.passthrough.md) | Terminal mode: hands mouse and keyboard back to the terminal so its native selection, copy, link clicking and scrolling work. Default: `toggle`. |
| [`tui.passthrough.key`](input/tui.passthrough.key.md) | Changes the chord that toggles terminal mode. Default: `ctrl+alt+p`. |
| [`tui.passthrough.active`](input/tui.passthrough.active.md) | Returns `0` while terminal mode is on. |
| [`tui.clipboard.copy`](input/tui.clipboard.copy.md) | Copies `TEXT` to the system clipboard through the terminal (OSC 52). |
| [`tui.clipboard.paste`](input/tui.clipboard.paste.md) | Prints the text of the last bracketed paste (no trailing newline). |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative input/tui.keys.suspend.md %}

{% include_relative input/tui.keys.suspend_key.md %}

{% include_relative input/tui.keys.suspended.md %}

{% include_relative input/tui.passthrough.md %}

{% include_relative input/tui.passthrough.key.md %}

{% include_relative input/tui.passthrough.active.md %}

{% include_relative input/tui.clipboard.copy.md %}

{% include_relative input/tui.clipboard.paste.md %}

</div>
<!-- /api -->

## Built-in actions

Use as `COMMAND` in `tui.bind`, `<bind action="…">`, `<button action="…">` or `tui.cmd.add`. All are bound by default and rebindable. More actions live with their modules: [`tui.action.text_keys`](widgets/tui.action.text_keys.md), [`tui.action.update`](apps/tui.action.update.md), [`tui.palette.open`](chrome/tui.palette.open.md).

<!-- api: tui.action.quit tui.action.quit_now tui.action.focus_next tui.action.focus_prev tui.action.focus_dir tui.action.unfocus tui.action.activate tui.action.click tui.action.scroll tui.action.page tui.action.scroll_top tui.action.scroll_bottom tui.action.pane_next tui.action.pane_prev tui.action.pane_dir tui.action.focus_pane tui.action.scroll_or_pane tui.action.paste tui.action.goto tui.action.goto_default tui.action.back tui.action.reload_page tui.action.redraw -->
| Function | Summary |
|---|---|
| [`tui.action.quit`](input/tui.action.quit.md) | Quits the app. Asks for confirmation first when the `confirm.quit` config key is `1`. |
| [`tui.action.quit_now`](input/tui.action.quit_now.md) | Quits the app without asking, regardless of `confirm.quit`. |
| [`tui.action.focus_next`](input/tui.action.focus_next.md) | Moves focus to the next focusable widget in creation order, wrapping around (`tab`). |
| [`tui.action.focus_prev`](input/tui.action.focus_prev.md) | Moves focus to the previous focusable widget (`shift+tab`). |
| [`tui.action.focus_dir`](input/tui.action.focus_dir.md) | Moves focus to the widget you would expect in that direction on screen. |
| [`tui.action.unfocus`](input/tui.action.unfocus.md) | Removes focus from the focused widget (`esc`). |
| [`tui.action.activate`](input/tui.action.activate.md) | Acts on the focused widget as Enter does: presses a button, toggles a checkbox, submits a text widget, opens a select, or runs a list/table action. |
| [`tui.action.click`](input/tui.action.click.md) | Handles a left press or drag: jumps a scrollbar, else acts on the widget under the pointer, else removes focus. |
| [`tui.action.scroll`](input/tui.action.scroll.md) | Scrolls the target pane by `N` lines (up/down, default 3) or columns (left/right, default 5). |
| [`tui.action.page`](input/tui.action.page.md) | Scrolls the target pane by one screen (its height minus 3 rows). |
| [`tui.action.scroll_top`](input/tui.action.scroll_top.md) | Scrolls the target pane to the top left. |
| [`tui.action.scroll_bottom`](input/tui.action.scroll_bottom.md) | Scrolls the target pane to the end. |
| [`tui.action.pane_next`](input/tui.action.pane_next.md) | Moves keyboard focus to the next pane worth visiting: scrollable panes and panes with two or more widgets. |
| [`tui.action.pane_prev`](input/tui.action.pane_prev.md) | Moves keyboard focus to the previous such pane. |
| [`tui.action.pane_dir`](input/tui.action.pane_dir.md) | Moves keyboard focus to the nearest such pane in that direction. |
| [`tui.action.focus_pane`](input/tui.action.focus_pane.md) | Moves keyboard focus into `PANE`: to the widget that last had focus there, else its first widget, else the pane itself becomes the scroll target. |
| [`tui.action.scroll_or_pane`](input/tui.action.scroll_or_pane.md) | Scrolls the target pane when it can scroll that way, else moves to the neighbouring pane (`alt+arrows`). |
| [`tui.action.paste`](input/tui.action.paste.md) | Inserts the pasted text (`TUI_EVENT_PASTE`) into the focused text widget, replacing the selection. |
| [`tui.action.goto`](input/tui.action.goto.md) | Opens a page, like [`tui.goto`](/api/markup/tui.goto.html). Does nothing without an argument. |
| [`tui.action.goto_default`](input/tui.action.goto_default.md) | Opens a page shipped with DABT (`$TUI_DEFAULTS_DIR/pages/NAME.xml`). Also reachable from the palette. |
| [`tui.action.back`](input/tui.action.back.md) | Returns to the previous page. Does nothing when there is no history. |
| [`tui.action.reload_page`](input/tui.action.reload_page.md) | Reloads the current page. Its `on_visit` runs again. |
| [`tui.action.redraw`](input/tui.action.redraw.md) | Recomputes the layout and repaints everything, like [`tui.relayout`](/api/core/tui.relayout.html). |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative input/tui.action.quit.md %}

{% include_relative input/tui.action.quit_now.md %}

{% include_relative input/tui.action.focus_next.md %}

{% include_relative input/tui.action.focus_prev.md %}

{% include_relative input/tui.action.focus_dir.md %}

{% include_relative input/tui.action.unfocus.md %}

{% include_relative input/tui.action.activate.md %}

{% include_relative input/tui.action.click.md %}

{% include_relative input/tui.action.scroll.md %}

{% include_relative input/tui.action.page.md %}

{% include_relative input/tui.action.scroll_top.md %}

{% include_relative input/tui.action.scroll_bottom.md %}

{% include_relative input/tui.action.pane_next.md %}

{% include_relative input/tui.action.pane_prev.md %}

{% include_relative input/tui.action.pane_dir.md %}

{% include_relative input/tui.action.focus_pane.md %}

{% include_relative input/tui.action.scroll_or_pane.md %}

{% include_relative input/tui.action.paste.md %}

{% include_relative input/tui.action.goto.md %}

{% include_relative input/tui.action.goto_default.md %}

{% include_relative input/tui.action.back.md %}

{% include_relative input/tui.action.reload_page.md %}

{% include_relative input/tui.action.redraw.md %}

</div>
<!-- /api -->
