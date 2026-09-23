# Widgets: text editing, lists, tables, select, progress

Besides label, button, checkbox and input, DABT has a multi-line **textarea**, a masked **password** field, a scrollable **list**, a **table**, a **select** (dropdown) and a **progress** bar. They are ordinary widgets: they take part in focus (Tab, arrows), theming (`class=`), hover and click, and `tui.get` / `tui.set` / `tui.update` work on them. API tables: [../api/reference.md](../api/reference.md#richer-widgets-and-text-editing).

```xml
<textarea id="notes"  pane="p" row="0" placeholder="type here..." rows="0" on_change="saved_draft"/>   <!-- rows 0 = fill the pane -->
<input    id="user"   pane="f" row="0" label="User:" submit="login"/>
<password id="pass"   pane="f" row="1" label="Pass:" submit="login"/>
<select   id="mode"   pane="f" row="3" label="Mode:" items="fast|balanced|careful" value="balanced" action="picked"/>
<progress id="job"    pane="f" row="5" label="Job:" value="0"/>
<list     id="files"  pane="d" row="0" rows="6" items="a|b|c" action="open_it" on_change="moved"/>
<table    id="rows"   pane="d" row="7" columns="File|Size" data="a.txt|1k;b.txt|2k" action="open_row"/>
```

The same widgets exist as calls: `tui.textarea ID PANE ROW [PLACEHOLDER] [ROWS] [SUBMIT_FN]`, `tui.password`, `tui.select`, `tui.progress`, `tui.list`, `tui.table` (see the reference). Data is set at runtime: `tui.list.set files a b c`, `tui.table.set rows "File|Size" "a.txt|1k"`, `tui.progress.set job 40`.

## Editing text (input, password, textarea)

All three share one engine ([../../lib/widgets/tui_text.sh](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/lib/widgets/tui_text.sh)). The text is `tui.get ID`; a textarea separates lines with `\n`.

| Do | Keys / mouse |
|---|---|
| Move | arrows; `ctrl+up` / `ctrl+down` previous / next **empty line** (textarea); `ctrl+left` / `ctrl+right` jump by word; `home` / `end` line start/end; `ctrl+home` / `ctrl+end` whole text; `up` `down` `pgup` `pgdn` in a textarea |
| Select | hold `shift` with any move key (`shift+up/down/home/end/pgup/pgdn/left/right`); `ctrl+shift+left/right` select to the previous / next word; `ctrl+shift+up/down` select up to the previous / next empty line (`alt+shift+arrows` do the same, for terminals that keep `ctrl+shift+arrows` for themselves: check yours with `tools/debug/keys.sh`); `ctrl+a` all; **drag** with the mouse; **double-click** a word; **triple-click** a line (all of an input) |
| Place the cursor | **click** |
| Delete | `backspace` `delete`; `ctrl+backspace` / `ctrl+w` / `alt+backspace` word left; `ctrl+delete` / `alt+d` word right; `ctrl+u` to line start; `ctrl+k` to line end |
| Copy / cut / paste | copy `ctrl+c`, `ctrl+insert`, `alt+c`; cut `ctrl+x`, `shift+delete`, `alt+x`; paste `ctrl+v`, `shift+insert`, `alt+v`, or your terminal's paste (arrives as one event) |
| Undo / redo | `ctrl+z` / `ctrl+y` (also `alt+z` / `alt+y`) |
| New line / submit | `enter` inserts a newline in a textarea and submits an input; `alt+enter` or `ctrl+enter` submits a textarea |

Notes:
- `up`/`down` at the first/last line of a textarea fall through, so focus can leave it; `esc` and `tab` also leave it.
- Every copy also goes to the terminal (OSC 52) and to `TUI_CLIPBOARD`. A **password** never copies or cuts, and shows `•`.
- Shift+click is reserved by most terminals for their own selection, so select with drag or `shift`+keys.
- Pasting into a single-line widget turns newlines into spaces; a textarea keeps them.
- Long lines scroll sideways (no soft wrap yet, see the roadmap). The textarea shows a scroll indicator in its last column.
- Bindings you make with `tui.bind` win over the editor except on the keys the editor consumes; use `--always` to take a key from it.

Programmatic access: `tui.text.selection ID`, `tui.text.select ID START END`, `tui.text.select_all ID`, `tui.text.cursor ID` (`ROW COL`, 1-based), `tui.text.set_cursor ID OFFSET`, `tui.text.insert ID TEXT`, `tui.text.delete_selection ID`, `tui.text.undo|redo ID`, `tui.text.line_count ID`, and `tui.on_change ID FN` (runs after every edit).

## Lists and tables

`up` / `down` / `pgup` / `pgdn` / `home` / `end` move the selection (at the first/last row up/down fall through to focus movement), `enter` or **double-click** runs `ACTION_FN ID`, a click selects, the wheel scrolls. Read the selection with `tui.list.selected ID` (index, `-1` none) and `tui.list.item ID`; for a table `tui.table.row ID` returns the row as `a|b|c`. `tui.on_change ID FN` fires whenever the selection moves. Table column widths follow the content and shrink (widest first) to fit.

## Select

One row: `Label  [ value ▾ ]`. Enter, space, Down or a click opens a picker (a `tui.choose` dialog); picking sets the value, redraws, runs `on_change` and `action`. Set options with `tui.select.set ID a b c`; `tui.get ID` is the current value.

## Progress

`tui.progress.set ID VALUE [MAX]` (or `tui.update ID 0-100`). Classes `.progress` (empty part) and `.progress_fill`.

## Theming

`.selection` (selected text), `.list_sel`, `.table_sel`, `.table_head`, `.progress`, `.progress_fill`, plus the usual `class=` / `:focus` / `:hover` on the widget itself. All have built-in fallbacks.

## Roadmap

Planned, not built:

- **Markdown.** A `mode="markdown"` on `<textarea>`: syntax highlighting while you type plus an optional live preview, and a read-only `<markdown>` widget that renders a document (the Docs page currently shows raw markdown). The editor is already shaped for it: every visible line is painted through one function (`_tui_text.paint`) that takes a slice of text, a selection range and a cursor column, so a per-widget highlighter (`tui.text.highlighter ID FN`, where `FN LINE` returns `START LEN STYLE` spans) plugs in without touching cursor, selection or undo. The preview would reuse the terminal renderers (`banner` for headings, `list`, `quote`, `box` for code blocks, `table`).
- **Soft wrap** and line numbers for the textarea.
- **Find / replace** (`ctrl+f`) as a small overlay on the modal layer.
- **Tab / indent** handling and multi-line indent for code-like text.
- **Table** sorting and column resize; multi-select in lists.

## Scrolling next to a text box

- **Mouse wheel** uses the usual wheel bindings: over a textarea / list / table it scrolls that widget (`shift+wheel` scrolls a textarea sideways); when the widget cannot scroll further that way the *same* binding scrolls the pane instead.
- **`alt+arrows`** scroll the pane (up/down/left/right) whenever it is scrollable that way, so it works while a text box has the keyboard. If the pane cannot scroll in that direction they move to the neighbouring pane as before (action `tui.action.scroll_or_pane`).

## The key list is a command

`f1` (or the command bar, `ctrl+p` -> "Help: text editing keybinds") opens a scrollable list of every text-editing key (`tui.action.text_keys`). The list is data (`TUI_TEXT_KEYS`), and the command bar is where an app adds its own commands: `tui.cmd.add my.help "Help: my shortcuts" show_my_help --group Help`; `tui.view TITLE TEXT` shows any text the same way.

## Keys belong to the app

While the app runs the terminal is in raw mode with `-isig -ixon -iexten -echo -icanon` (set in `tui.init`): `ctrl+c`, `ctrl+z`, `ctrl+s`, `ctrl+q`, `ctrl+v` and `ctrl+y` are delivered to DABT as ordinary keys, nothing is echoed, and nothing typed reaches the shell. Consequences: `ctrl+c` no longer interrupts the app (quit is `q` / `ctrl+q`, or `tui.action.quit`), and on exit `tui.cleanup` discards unread input (stray mouse reports, keys typed during shutdown) before restoring your shell's settings.
