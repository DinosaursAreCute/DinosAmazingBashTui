# Widgets: forms & text editing

`lib/tui.sh` (basic widgets), `lib/widgets/tui_widgets.sh`, `lib/widgets/tui_text.sh` - the widget constructors and the text-editing engine shared by input, password and textarea. Guide: [../guide/widgets.md](../guide/widgets.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

Constructors take `ID PANE ROW ...`. `ROW` is 0-based inside the pane's content area. A missing `ID` or `PANE` prints an error and skips the widget. Functions return `0` unless their entry says otherwise.

Every widget callback gets the widget id first, so one function can serve several widgets:

| Widget | Callback | Called as |
|---|---|---|
| button, list, table, select | action | `FN ID` |
| checkbox | action | `FN ID VALUE` (value `0`/`1`) |
| input, password, textarea | submit | `FN ID TEXT` |
| any | [`tui.on_change`](widgets/tui.on_change.md) | `FN ID` |

## Widgets

<!-- api: tui.label tui.button tui.input tui.checkbox tui.checkbox.toggle tui.get tui.set tui.update tui.set_label tui.get.label tui.on_action tui.on_submit tui.align tui.valign tui.minsize tui.maxsize tui.pad tui.label_align tui.label_width tui.input.retain tui.input.blur_on_submit tui.input.sticky tui.focus -->
| Function | Summary |
|---|---|
| [`tui.label`](widgets/tui.label.md) | Creates a static text widget. |
| [`tui.button`](widgets/tui.button.md) | Creates a focusable button. |
| [`tui.input`](widgets/tui.input.md) | Creates a single-line text input. |
| [`tui.checkbox`](widgets/tui.checkbox.md) | Creates a checkbox. |
| [`tui.checkbox.toggle`](widgets/tui.checkbox.toggle.md) | Flips a checkbox, redraws it and calls its action as `ACTION ID VALUE`, as a click would. |
| [`tui.get`](widgets/tui.get.md) | Prints a widget's value, without a trailing newline. |
| [`tui.set`](widgets/tui.set.md) | Sets a widget's value without redrawing it. |
| [`tui.update`](widgets/tui.update.md) | Sets a widget's value and redraws the widget. |
| [`tui.set_label`](widgets/tui.set_label.md) | Changes the caption of a button or checkbox, or the text of a label, and redraws it. |
| [`tui.get.label`](widgets/tui.get.label.md) | Prints the caption of a widget: button text, checkbox label, input label or label text. |
| [`tui.on_action`](widgets/tui.on_action.md) | Sets or replaces the action function of a widget. Buttons, lists and tables call it as `FN ID`; checkboxes as `FN ID VALUE`. |
| [`tui.on_submit`](widgets/tui.on_submit.md) | Sets or replaces the submit function of an input, password or textarea, called as `FN ID TEXT`. |
| [`tui.align`](widgets/tui.align.md) | Sets the horizontal alignment of one widget, overriding the pane default. |
| [`tui.valign`](widgets/tui.valign.md) | Sets the vertical anchor of one widget, overriding the pane default. |
| [`tui.minsize`](widgets/tui.minsize.md) | Sets the minimum width of a widget in columns. |
| [`tui.maxsize`](widgets/tui.maxsize.md) | Sets the maximum width of a widget in columns. |
| [`tui.pad`](widgets/tui.pad.md) | Sets blank columns and rows around one widget. An empty value is left unchanged. |
| [`tui.label_align`](widgets/tui.label_align.md) | Aligns an input label inside its label column. |
| [`tui.label_width`](widgets/tui.label_width.md) | Gives an input label a fixed column width, so fields in a form line up. |
| [`tui.input.retain`](widgets/tui.input.retain.md) | Sets whether an input keeps focus after Enter. |
| [`tui.input.blur_on_submit`](widgets/tui.input.blur_on_submit.md) | Old name for `tui.input.retain ID false`. |
| [`tui.input.sticky`](widgets/tui.input.sticky.md) | With `true` (default), clicking empty space no longer takes focus away from the input; Esc and Tab still do. |
| [`tui.focus`](widgets/tui.focus.md) | Focuses a widget. Its pane becomes the keyboard pane. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative widgets/tui.label.md %}

{% include_relative widgets/tui.button.md %}

{% include_relative widgets/tui.input.md %}

{% include_relative widgets/tui.checkbox.md %}

{% include_relative widgets/tui.checkbox.toggle.md %}

{% include_relative widgets/tui.get.md %}

{% include_relative widgets/tui.set.md %}

{% include_relative widgets/tui.update.md %}

{% include_relative widgets/tui.set_label.md %}

{% include_relative widgets/tui.get.label.md %}

{% include_relative widgets/tui.on_action.md %}

{% include_relative widgets/tui.on_submit.md %}

{% include_relative widgets/tui.align.md %}

{% include_relative widgets/tui.valign.md %}

{% include_relative widgets/tui.minsize.md %}

{% include_relative widgets/tui.maxsize.md %}

{% include_relative widgets/tui.pad.md %}

{% include_relative widgets/tui.label_align.md %}

{% include_relative widgets/tui.label_width.md %}

{% include_relative widgets/tui.input.retain.md %}

{% include_relative widgets/tui.input.blur_on_submit.md %}

{% include_relative widgets/tui.input.sticky.md %}

{% include_relative widgets/tui.focus.md %}

</div>
<!-- /api -->

## Richer widgets

Key tables and mouse behaviour: [../guide/widgets.md](../guide/widgets.md). Markup tags: `<password> <textarea> <list> <table> <select> <progress>` (attributes in `share/tui.xsd`). Theme classes (all optional): `.list_sel .table_head .table_sel .progress .progress_fill .select .selection`.

<!-- api: tui.password tui.textarea tui.list tui.table tui.select tui.progress tui.list.set tui.list.add tui.list.clear tui.list.select tui.list.selected tui.list.item tui.list.count tui.table.set tui.table.add tui.table.clear tui.table.count tui.table.select tui.table.selected tui.table.row tui.select.set tui.select.index tui.select.pick tui.progress.set tui.on_change -->
| Function | Summary |
|---|---|
| [`tui.password`](widgets/tui.password.md) | Creates a single-line input that shows `•` for each character. |
| [`tui.textarea`](widgets/tui.textarea.md) | Creates a multi-line text editor. |
| [`tui.list`](widgets/tui.list.md) | Creates a scrollable single-choice list. |
| [`tui.table`](widgets/tui.table.md) | Creates a scrollable table: a header row plus rows of `\|`-separated cells, one selectable row at a time. |
| [`tui.select`](widgets/tui.select.md) | Creates a one-row dropdown. Enter, Space, Down or a click opens a picker dialog. |
| [`tui.progress`](widgets/tui.progress.md) | Creates a progress bar showing 0–100 %. Not focusable. |
| [`tui.list.set`](widgets/tui.list.set.md) | Replaces all items and selects the first one (none when empty). |
| [`tui.list.add`](widgets/tui.list.add.md) | Appends items. Selects the first item when nothing was selected. |
| [`tui.list.clear`](widgets/tui.list.clear.md) | Removes all items and clears the selection. |
| [`tui.list.select`](widgets/tui.list.select.md) | Moves the selection to `INDEX` (0-based), clamped to the list. A negative index clears it. |
| [`tui.list.selected`](widgets/tui.list.selected.md) | Prints the selected index, or `-1` when nothing is selected. |
| [`tui.list.item`](widgets/tui.list.item.md) | Prints the item at `INDEX`, default the selected one. Prints nothing for an index out of range. |
| [`tui.list.count`](widgets/tui.list.count.md) | Prints the number of items. |
| [`tui.table.set`](widgets/tui.table.set.md) | Replaces the header and all rows, and selects the first row. |
| [`tui.table.add`](widgets/tui.table.add.md) | Appends rows (`\|`-separated cells). Selects the first row when nothing was selected. |
| [`tui.table.clear`](widgets/tui.table.clear.md) | Removes all rows and clears the selection. The header is kept. |
| [`tui.table.count`](widgets/tui.table.count.md) | Prints the number of rows (the header not counted). |
| [`tui.table.select`](widgets/tui.table.select.md) | Moves the selection to row `INDEX` (0-based), clamped. Does not call `on_change`. |
| [`tui.table.selected`](widgets/tui.table.selected.md) | Prints the selected row index, or `-1`. |
| [`tui.table.row`](widgets/tui.table.row.md) | Prints a row as `a\|b\|c`, default the selected one. |
| [`tui.select.set`](widgets/tui.select.set.md) | Replaces the options. The current value stays selected when it is among the new options. |
| [`tui.select.index`](widgets/tui.select.index.md) | Prints the index of the current value among the options, or `-1`. |
| [`tui.select.pick`](widgets/tui.select.pick.md) | Chooses option `INDEX` (0-based) as if the user picked it: sets the value, redraws, then calls the `on_change` function and the action. |
| [`tui.progress.set`](widgets/tui.progress.set.md) | Sets a progress bar to `VALUE` out of `MAX` and redraws it. |
| [`tui.on_change`](widgets/tui.on_change.md) | Sets a function called as `FN ID` whenever the widget changes through the user. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative widgets/tui.password.md %}

{% include_relative widgets/tui.textarea.md %}

{% include_relative widgets/tui.list.md %}

{% include_relative widgets/tui.table.md %}

{% include_relative widgets/tui.select.md %}

{% include_relative widgets/tui.progress.md %}

{% include_relative widgets/tui.list.set.md %}

{% include_relative widgets/tui.list.add.md %}

{% include_relative widgets/tui.list.clear.md %}

{% include_relative widgets/tui.list.select.md %}

{% include_relative widgets/tui.list.selected.md %}

{% include_relative widgets/tui.list.item.md %}

{% include_relative widgets/tui.list.count.md %}

{% include_relative widgets/tui.table.set.md %}

{% include_relative widgets/tui.table.add.md %}

{% include_relative widgets/tui.table.clear.md %}

{% include_relative widgets/tui.table.count.md %}

{% include_relative widgets/tui.table.select.md %}

{% include_relative widgets/tui.table.selected.md %}

{% include_relative widgets/tui.table.row.md %}

{% include_relative widgets/tui.select.set.md %}

{% include_relative widgets/tui.select.index.md %}

{% include_relative widgets/tui.select.pick.md %}

{% include_relative widgets/tui.progress.set.md %}

{% include_relative widgets/tui.on_change.md %}

</div>
<!-- /api -->

## Text editing

For input, password and textarea widgets. Offsets are 0-based character positions in the whole text. `TUI_CLIPBOARD` holds the text of the last copy or cut inside a text widget; every copy is also sent to the terminal clipboard ([`tui.clipboard.copy`](input/tui.clipboard.copy.md)).

<!-- api: tui.text.selection tui.text.select tui.text.select_all tui.text.cursor tui.text.set_cursor tui.text.insert tui.text.delete_selection tui.text.undo tui.text.redo tui.text.line_count tui.action.text_keys -->
| Function | Summary |
|---|---|
| [`tui.text.selection`](widgets/tui.text.selection.md) | Prints the selected text of a text widget (nothing when nothing is selected). |
| [`tui.text.select`](widgets/tui.text.select.md) | Selects characters `START` to `END` (0-based offsets into the whole text) and redraws. Offsets beyond the end are clamped. |
| [`tui.text.select_all`](widgets/tui.text.select_all.md) | Selects the whole text and redraws. |
| [`tui.text.cursor`](widgets/tui.text.cursor.md) | Prints the cursor position as `ROW COL` (1-based). |
| [`tui.text.set_cursor`](widgets/tui.text.set_cursor.md) | Moves the cursor to character `OFFSET` (0-based, clamped) and clears the selection. |
| [`tui.text.insert`](widgets/tui.text.insert.md) | Inserts `TEXT` at the cursor, replacing the selection, as typing would. The change can be undone and calls the `on_change` function. |
| [`tui.text.delete_selection`](widgets/tui.text.delete_selection.md) | Deletes the selected text. Returns `1` when nothing is selected. |
| [`tui.text.undo`](widgets/tui.text.undo.md) | Undoes the last edit (`ctrl+z`/`alt+z`). Returns `1` when there is nothing to undo. |
| [`tui.text.redo`](widgets/tui.text.redo.md) | Redoes the last undone edit (`ctrl+y`/`alt+y`). Returns `1` when there is nothing to redo. |
| [`tui.text.line_count`](widgets/tui.text.line_count.md) | Prints the number of lines in a text widget (`1` for an input). |
| [`tui.action.text_keys`](widgets/tui.action.text_keys.md) | Opens a scrollable list of every text-editing key. Bound to `f1` by default. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative widgets/tui.text.selection.md %}

{% include_relative widgets/tui.text.select.md %}

{% include_relative widgets/tui.text.select_all.md %}

{% include_relative widgets/tui.text.cursor.md %}

{% include_relative widgets/tui.text.set_cursor.md %}

{% include_relative widgets/tui.text.insert.md %}

{% include_relative widgets/tui.text.delete_selection.md %}

{% include_relative widgets/tui.text.undo.md %}

{% include_relative widgets/tui.text.redo.md %}

{% include_relative widgets/tui.text.line_count.md %}

{% include_relative widgets/tui.action.text_keys.md %}

</div>
<!-- /api -->
