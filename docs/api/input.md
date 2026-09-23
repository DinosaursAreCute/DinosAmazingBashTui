# Input: keys, mouse & actions

`lib/input/tui_input.sh` - key/mouse binding tables, dispatch, defaults, pass-through, and the built-in actions bindable from `tui.bind`, `<bind action="…">`, `<button action="…">` or `tui.cmd.add`. Guide: [../guide/input-bindings.md](../guide/input-bindings.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

## Input and bindings

| Function | Parameters | Description |
|---|---|---|
| `tui.bind` | `KEY COMMAND [--pane ID] [--pass] [--always] [--page] [--user] [--desc TEXT]` | Bind KEY. `--pane`: only when that pane is keyboard/pointer target. `--pass`: run this, then the default binding too. `--always`: also fire while typing in an input. `--page`: cleared on page change. `--user`: a user bind (persisted by `tui.bind.save`). COMMAND may chain with `;`. |
| `tui.unbind` | `KEY [--pane ID] [--user]` | Remove a binding. |
| `tui.bind.reset` | `[--user]` | Drop all code binds, or (`--user`) all user binds. |
| `tui.bind.list` | | Print bind rows. |
| `tui.bind.table` | | → `_TBL` aligned text table of all bindings. |
| `tui.bind.defaults` | `[FILE]` | (Re)load default binds (default `share/defaults/keybinds.xml`). |
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
| `tui.action.quit` | | Stop the app (asks first when the `confirm.quit` setting is on). `tui.action.quit_now` never asks. |
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
| `tui.action.scroll_or_pane` | `up\|down\|left\|right` | Scroll the pane when it can scroll that way, else move to the neighbouring pane (default `alt+arrows`). |
| `tui.action.text_keys` | | Scrollable list of every text-editing key (default `f1`). |
| `tui.action.paste` | | Insert `TUI_EVENT_PASTE` into the focused input. |
| `tui.action.goto` | `PAGE_FILE` | Go to a page. |
| `tui.action.goto_default` | `settings\|keybinds` | Open a page shipped with DABT (`share/defaults/pages/`). |
| `tui.action.back` | | Return to the previous page. |
| `tui.action.reload_page` | | Reload the current page. |
| `tui.action.redraw` | | Full relayout and repaint. |
