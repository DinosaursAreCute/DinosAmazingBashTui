# Chrome: commands, modals, dialogs & footer

`lib/chrome/tui_cmd.sh`, `lib/chrome/tui_modal.sh`, `lib/chrome/tui_dialog.sh`, `lib/chrome/tui_footer.sh` - the command palette, the overlay/modal layer dialogs and toasts are built on, the dialogs themselves, and the `<footer/>` key-hint bar. ← [API index](README.md) for the full module list and a task-oriented tour with examples.

## Commands and palette

The command bar (default `ctrl+p`) lists registered commands and runs one.

| Function | Parameters | Description |
|---|---|---|
| `tui.cmd.add` | `ID TITLE ACTION [--group G] [--desc D] [--when FN] [--key KEY]` | Register a command. `--when FN`: only listed while `FN` succeeds. `--key`: also bind a key. Re-adding an ID replaces it. |
| `tui.cmd.remove` | `ID` | Unregister. |
| `tui.cmd.run` | `ID` | Run a command by id. |
| `tui.cmd.list` | | Print `ID GROUP TITLE ACTION` per command. |
| `tui.cmd.load` | `FILE` | Load `<cmd .../>` lines (same style as `share/defaults/commands.xml`). |
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

## Dialogs and notifications

Callback style: a dialog returns at once and calls your function after the user answers (when the dialog is gone and the screen repainted, so the callback may open the next dialog or change page). A CMD is a function name plus optional fixed args (`"do_delete file1"`). One dialog at a time; opening a second replaces the first. `TUI_DIALOG_RESULT` holds `yes|no|ok|submit|cancel|choose` when the callback runs.

| Function | Parameters | Description |
|---|---|---|
| `tui.confirm` | `MESSAGE [ON_YES [ON_NO]] [flags]` | Yes / No. `y` yes, `n`/Esc no, arrows/Tab move, Enter picks, click works. `--danger` makes Yes red and defaults to No. |
| `tui.message` | `MESSAGE [ON_CLOSE] [flags]` | Text with an OK button. |
| `tui.prompt` | `MESSAGE ON_SUBMIT [flags]` | One-line editor (cursor, Home/End, Delete, ctrl+u/k/w, paste). `ON_SUBMIT` gets the text as its last arg. `--value TEXT`, `--placeholder TEXT`, `--validate FN` (`FN VALUE` returns non-zero to reject; set `TUI_DIALOG_ERROR` to say why, the dialog stays), `--cancel CMD`. |
| `tui.choose` | `TITLE ON_CHOOSE ITEM... [flags]` | List picker: arrows/j/k/PgUp/PgDn, Enter, digits 1-9, click, wheel. `ON_CHOOSE` gets `INDEX` (0-based) and `ITEM`. `--message TEXT`, `--selected N`, `--cancel CMD`. |
| `tui.view` | `TITLE TEXT [--width N] [--close CMD]` | Scrollable read-only text (help screens). Up/Down/PgUp/PgDn/Home/End, wheel; Esc / q / Enter close. |
| `tui.dialog.close` | | Dismiss the open dialog without calling anything. |
| `tui.dialog.active` | | Status 0 while a dialog is open. |
| `tui.notify` | `MESSAGE [LEVEL] [SECONDS]` | Toast at the bottom-right above the footer. LEVEL `info` (default), `success`, `warn`, `error`; SECONDS default 5, `0` = sticky. Up to 5 stack (oldest dropped); toasts survive page changes. → `TUI_NOTIFY_ID`. |
| `tui.notify.clear` | `[ID]` | Dismiss one toast, or all. |
| `tui.notify.count` | | Print the number of toasts showing. |
| `tui.notify.position` | `[POS]` | Where toasts appear: `bottom-right` (default), `bottom-left`, `bottom-center`, `top-right`, `top-left`, `top-center`. No argument prints it. Persisted as config `notify.position` (default Settings page has a button). |
| `tui.notify.seconds` | `[N]` | Default toast lifetime in seconds (default 5, `0` = until dismissed). Persisted as `notify.seconds`. |

Common flags: `--title T`, `--width N`, `--ok L`, `--yes L`, `--no L`, `--danger`, `--default yes|no`. Theme classes (all optional): `.dialog .dialog_title .dialog_btn .dialog_btn_sel .dialog_danger .dialog_dim .dialog_error` and `.toast .toast_success .toast_warn .toast_error`. Config: `tui.config.set confirm.quit 1` makes `tui.action.quit` ask first (`tui.action.quit_now` never asks).

## Footer

| Function | Parameters | Description |
|---|---|---|
| `tui.footer.set` | `ITEMS` | Declare the footer (what `<footer items="…"/>` calls). Records state only. |
| `tui.footer.show` | `[ITEMS]` | Set and show, with relayout (the root pane gives up the last row). |
| `tui.footer.add` | `KEY LABEL [WHEN_FN]` | Append an item. |
| `tui.footer.hide` | | Remove the footer. |

ITEMS = `KEY|Label[|WHEN_FN];…`. KEY may be literal (`ctrl+s`) or `@ACTION` (shows the key currently bound to that action, so rebinding updates the footer). `WHEN_FN` hides the item while it fails.
