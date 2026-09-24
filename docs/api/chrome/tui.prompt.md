### `tui.prompt`

```bash
tui.prompt MESSAGE ON_SUBMIT [flags]
```

Shows a one-line text input dialog. `ON_SUBMIT` is called with the text appended as its last argument.

**Options**

- `--value TEXT`: initial text.
- `--placeholder TEXT`: grey hint while empty.
- `--validate FN`: called as `FN TEXT` on submit. A non-zero return keeps the dialog open; set `TUI_DIALOG_ERROR` to show why.
- `--cancel CMD`: runs on Esc or Cancel.
- Common: `--title`, `--width`, `--ok`.

**Notes**

- Supports the text-editing keys of an input (cursor, Home/End, `ctrl+u`/`ctrl+k`/`ctrl+w`, paste).

**Example**

```bash
name_ok() { [[ -n "$1" && "$1" != */* ]] || { TUI_DIALOG_ERROR="no slashes, not empty"; return 1; }; }
tui.prompt "New name:" do_rename --value "$old" --validate name_ok
do_rename() { mv -- "$old" "$1" && tui.notify "Renamed to $1" success; }
```
