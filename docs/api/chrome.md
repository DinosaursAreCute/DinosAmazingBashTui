# Chrome: commands, modals, dialogs & footer

`lib/chrome/tui_cmd.sh`, `lib/chrome/tui_modal.sh`, `lib/chrome/tui_dialog.sh`, `lib/chrome/tui_footer.sh` - the command palette, the overlay/modal layer dialogs and toasts are built on, the dialogs themselves, and the `<footer/>` key-hint bar. ← [API index](README.md) for the full module list and a task-oriented tour with examples.

Functions return `0` unless their entry says otherwise.

## Commands and palette

The command bar (default `ctrl+p` or `:`) lists registered commands and runs one. DABT's own commands are registered the same way, from `share/defaults/commands.xml`.

<!-- api: tui.cmd.add tui.cmd.remove tui.cmd.run tui.cmd.list tui.cmd.load tui.cmd.provider tui.palette.open tui.palette.close -->
| Function | Summary |
|---|---|
| [`tui.cmd.add`](chrome/tui.cmd.add.md) | Registers a command in the command palette. |
| [`tui.cmd.remove`](chrome/tui.cmd.remove.md) | Unregisters a command. A key bound with `--key` stays bound; remove it with [`tui.unbind`](/api/input/tui.unbind.html). |
| [`tui.cmd.run`](chrome/tui.cmd.run.md) | Runs a command by id. Returns `1` and prints a message on stderr for an unknown id. |
| [`tui.cmd.list`](chrome/tui.cmd.list.md) | Prints every command as `ID<TAB>GROUP<TAB>TITLE<TAB>ACTION`, in registration order. |
| [`tui.cmd.load`](chrome/tui.cmd.load.md) | Registers the commands in an XML file, one `<cmd id="…" title="…" action="…" [group="…"] [desc="…"] [when="…"] [key="…"]/>` per line. |
| [`tui.cmd.provider`](chrome/tui.cmd.provider.md) | Registers a function that runs every time the palette opens and adds commands that depend on current state. |
| [`tui.palette.open`](chrome/tui.palette.open.md) | Opens the command palette, optionally with the search prefilled. Bound to `ctrl+p` and `:` by default. |
| [`tui.palette.close`](chrome/tui.palette.close.md) | Closes the palette if it is open. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative chrome/tui.cmd.add.md %}

{% include_relative chrome/tui.cmd.remove.md %}

{% include_relative chrome/tui.cmd.run.md %}

{% include_relative chrome/tui.cmd.list.md %}

{% include_relative chrome/tui.cmd.load.md %}

{% include_relative chrome/tui.cmd.provider.md %}

{% include_relative chrome/tui.palette.open.md %}

{% include_relative chrome/tui.palette.close.md %}

</div>
<!-- /api -->

## Modal and overlay

An overlay is a draw function called after every repaint, so it stays on top. A modal is an overlay that also captures all input.

<!-- api: tui.overlay.add tui.overlay.remove tui.overlay.box tui.modal.open tui.modal.close tui.modal.active tui.modal.redraw -->
| Function | Summary |
|---|---|
| [`tui.overlay.add`](chrome/tui.overlay.add.md) | Registers a function that draws on top of the panes after every repaint. |
| [`tui.overlay.remove`](chrome/tui.overlay.remove.md) | Unregisters an overlay. |
| [`tui.overlay.box`](chrome/tui.overlay.box.md) | Draws a framed box at an absolute position. Meant for overlay and modal draw functions. |
| [`tui.modal.open`](chrome/tui.modal.open.md) | Opens a modal: an overlay that receives all input until it is closed. |
| [`tui.modal.close`](chrome/tui.modal.close.md) | Closes the open modal and repaints the screen under it. |
| [`tui.modal.active`](chrome/tui.modal.active.md) | Returns `0` while a modal is open (or, with `NAME`, while that modal is open). |
| [`tui.modal.redraw`](chrome/tui.modal.redraw.md) | Redraws all overlays now. Call it after changing the state a modal draws. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative chrome/tui.overlay.add.md %}

{% include_relative chrome/tui.overlay.remove.md %}

{% include_relative chrome/tui.overlay.box.md %}

{% include_relative chrome/tui.modal.open.md %}

{% include_relative chrome/tui.modal.close.md %}

{% include_relative chrome/tui.modal.active.md %}

{% include_relative chrome/tui.modal.redraw.md %}

</div>
<!-- /api -->

## Dialogs and notifications

Dialogs never block: they return at once and call your function after the user answers, when the dialog is gone and the screen repainted, so the callback may open the next dialog or change page. A callback is a function name plus optional fixed arguments (`"do_delete file1"`); answers such as the prompt text are appended. One dialog at a time: opening a second replaces the first. `TUI_DIALOG_RESULT` holds `yes`, `no`, `ok`, `submit`, `cancel` or `choose` while the callback runs.

Common flags: `--title T`, `--width N`, `--ok LABEL`, `--yes LABEL`, `--no LABEL`, `--danger`, `--default yes|no`. Theme classes (all optional): `.dialog .dialog_title .dialog_btn .dialog_btn_sel .dialog_danger .dialog_dim .dialog_error` and `.toast .toast_success .toast_warn .toast_error`.

<!-- api: tui.confirm tui.message tui.prompt tui.choose tui.view tui.dialog.close tui.dialog.active tui.notify tui.notify.clear tui.notify.count tui.notify.position tui.notify.seconds -->
| Function | Summary |
|---|---|
| [`tui.confirm`](chrome/tui.confirm.md) | Shows a Yes/No dialog and returns immediately; the callback runs after the user answers. |
| [`tui.message`](chrome/tui.message.md) | Shows a message with an OK button. `ON_CLOSE` runs after OK, Enter or Esc. |
| [`tui.prompt`](chrome/tui.prompt.md) | Shows a one-line text input dialog. `ON_SUBMIT` is called with the text appended as its last argument. |
| [`tui.choose`](chrome/tui.choose.md) | Shows a list picker. `ON_CHOOSE` is called with the 0-based index and the item text appended. |
| [`tui.view`](chrome/tui.view.md) | Shows scrollable read-only text, for help screens and logs. |
| [`tui.dialog.close`](chrome/tui.dialog.close.md) | Closes the open dialog without calling any of its callbacks. |
| [`tui.dialog.active`](chrome/tui.dialog.active.md) | Returns `0` while a dialog is open. |
| [`tui.notify`](chrome/tui.notify.md) | Shows a toast notification that disappears on its own. |
| [`tui.notify.clear`](chrome/tui.notify.clear.md) | Dismisses one toast by id, or all toasts, and repaints what they covered. |
| [`tui.notify.count`](chrome/tui.notify.count.md) | Prints the number of toasts showing. |
| [`tui.notify.position`](chrome/tui.notify.position.md) | Sets where toasts appear, or prints the current position without an argument. |
| [`tui.notify.seconds`](chrome/tui.notify.seconds.md) | Sets the default toast lifetime in seconds (decimals allowed, `0` = until cleared), or prints it without an argument. Default: `5`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative chrome/tui.confirm.md %}

{% include_relative chrome/tui.message.md %}

{% include_relative chrome/tui.prompt.md %}

{% include_relative chrome/tui.choose.md %}

{% include_relative chrome/tui.view.md %}

{% include_relative chrome/tui.dialog.close.md %}

{% include_relative chrome/tui.dialog.active.md %}

{% include_relative chrome/tui.notify.md %}

{% include_relative chrome/tui.notify.clear.md %}

{% include_relative chrome/tui.notify.count.md %}

{% include_relative chrome/tui.notify.position.md %}

{% include_relative chrome/tui.notify.seconds.md %}

</div>
<!-- /api -->

## Footer

<!-- api: tui.footer.set tui.footer.show tui.footer.add tui.footer.hide -->
| Function | Summary |
|---|---|
| [`tui.footer.set`](chrome/tui.footer.set.md) | Declares the footer bar, as `<footer/>` does. Records the items only; the page layout then leaves the last row free. |
| [`tui.footer.show`](chrome/tui.footer.show.md) | Sets and shows the footer at runtime, then relayouts so the outermost pane gives up the last row. Empty `ITEMS` shows the default items. |
| [`tui.footer.add`](chrome/tui.footer.add.md) | Appends one item to the footer (to the default items when none were set) and shows it. |
| [`tui.footer.hide`](chrome/tui.footer.hide.md) | Removes the footer and gives the last row back to the panes. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative chrome/tui.footer.set.md %}

{% include_relative chrome/tui.footer.show.md %}

{% include_relative chrome/tui.footer.add.md %}

{% include_relative chrome/tui.footer.hide.md %}

</div>
<!-- /api -->
