# Widgets: forms & text editing

`lib/widgets/tui_widgets.sh`, `lib/widgets/tui_text.sh` - the widget constructors and the text-editing engine shared by input, password and textarea. Guide: [../guide/widgets.md](../guide/widgets.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

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

## Richer widgets and text editing

Details and key tables: [../guide/widgets.md](../guide/widgets.md). Markup tags: `<password> <textarea> <list> <table> <select> <progress>` (attributes in `share/tui.xsd`).

| Function | Parameters | Description |
|---|---|---|
| `tui.password` | `ID PANE ROW [PLACEHOLDER] [LABEL] [SUBMIT_FN]` | Masked single-line input; value via `tui.get`. Never copies or cuts. |
| `tui.textarea` | `ID PANE ROW [PLACEHOLDER] [ROWS] [SUBMIT_FN]` | Multi-line editor. `ROWS` omitted or `0` = fill the pane. `alt+enter` / `ctrl+enter` submit. |
| `tui.list` | `ID PANE ROW [ACTION_FN] [ROWS]` | Scrollable single-choice list. `ACTION_FN ID` on Enter / double-click. |
| `tui.table` | `ID PANE ROW [ACTION_FN] [ROWS]` | Header row + rows of `\|`-separated cells. |
| `tui.select` | `ID PANE ROW LABEL [ACTION_FN]` | One row; opens a picker. Value via `tui.get`. |
| `tui.progress` | `ID PANE ROW [LABEL]` | Bar, 0-100. |
| `tui.list.set` / `tui.list.add` / `tui.list.clear` | `ID ITEM...` / `ID ITEM...` / `ID` | Replace / append / empty the items. |
| `tui.list.select` | `ID INDEX` | Move the selection. |
| `tui.list.selected` | `ID` | Print the selected index (`-1` none). |
| `tui.list.item` | `ID [INDEX]` | Print an item (default: the selected one). |
| `tui.list.count` | `ID` | Print the number of items. |
| `tui.table.set` | `ID "H1\|H2" "a\|b"...` | Set header and rows. |
| `tui.table.add` / `.clear` / `.count` / `.select` / `.selected` / `.row` | as the list functions | `row` prints the row as `a\|b\|c`. |
| `tui.select.set` | `ID ITEM...` | Set the options. |
| `tui.select.index` / `tui.select.pick` | `ID` / `ID INDEX` | Index of the value / choose an option (runs `on_change` and `action`). |
| `tui.progress.set` | `ID VALUE [MAX]` | Set the bar (percent of MAX, default 100). |
| `tui.on_change` | `ID FN` | `FN ID` after an edit (text), selection move (list, table) or new value (select). |
| `tui.text.selection` | `ID` | Print the selected text. |
| `tui.text.select` | `ID START END` | Select an offset range. |
| `tui.text.select_all` | `ID` | Select everything. |
| `tui.text.cursor` | `ID` | Print `ROW COL` (1-based). |
| `tui.text.set_cursor` | `ID OFFSET` | Move the cursor, clearing the selection. |
| `tui.text.insert` | `ID TEXT` | Insert at the cursor, replacing the selection. |
| `tui.text.delete_selection` | `ID` | Delete the selection. |
| `tui.text.undo` / `tui.text.redo` | `ID` | Undo / redo (`alt+z` / `alt+y`). |
| `tui.text.line_count` | `ID` | Print the number of lines. |
| `TUI_CLIPBOARD` | variable | Text of the last copy / cut inside a text widget. |
