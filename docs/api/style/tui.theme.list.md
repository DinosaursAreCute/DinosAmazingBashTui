### `tui.theme.list`

```bash
tui.theme.list
```

Prints every selectable theme overlay as `NAME<TAB>FILE`, one per line, sorted by name.

**Notes**

- Lists every `*.css` in DABT's installed themes directory (`$TUI_DEFAULTS_DIR/themes`) plus the app's own `TUI_THEMES_DIR` (set by [`tui.start`](/api/core/tui.start.html) to `<app dir>/themes` when that folder exists). An app theme with the same name wins.
- The Settings page and the command palette list exactly these, so a `.css` dropped into either directory shows up in both.

**Example**

```bash
while IFS=$'\t' read -r name file; do echo "$name -> $file"; done < <(tui.theme.list)
```

**See also:** [`tui.theme.pick`](/api/style/tui.theme.pick.html)
