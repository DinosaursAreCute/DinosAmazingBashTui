### `tui.validate.rule`

```bash
tui.validate.rule page|element|end FN
```

Registers a custom check.

**Parameters**

- `page`: `FN` runs once before a page is walked.
- `element`: `FN` runs for every element, with `TUI_V_FILE`, `TUI_V_LINE`, `TUI_V_COL`, `TUI_V_TAG`, `TUI_V_RAW`, `TUI_V_SELFCLOSE`, `TUI_V_DEPTH`, `TUI_V_PARENT_TAG`, `TUI_V_PARENT_ID`, `TUI_V_PARENT_SPLIT`, `TUI_V_GRANDPARENT_SPLIT` set. Read attributes with [`tui.validate.attr`](/api/markup/tui.validate.attr.html).
- `end`: `FN` runs after the walk, with `TUI_V_PAGE` and the maps `TUI_V_PANES`, `TUI_V_PANE_SPLIT`, `TUI_V_WIDGETS`, `TUI_V_WIDGET_PANE`, `TUI_V_WIDGET_PANE_AT` (locations are `file|line|col`).

**Returns:** `1` for another kind.

**Notes**

- Report with [`tui.validate.error`](/api/markup/tui.validate.error.html) / [`tui.validate.warn`](/api/markup/tui.validate.warn.html).
- Register rules after sourcing `tui.sh` and before `tui.start`.
- A clean validation is remembered per page set and file mtimes. After adding a rule, pages that already passed are not checked again until a page or include changes; delete `$TUI_HOME/cache/validated` (or run `dabt clear-cache`) to force it.

**Example**

```bash
no_empty_title() {
    [[ "$TUI_V_TAG" == pane ]] || return 0
    tui.validate.attr title && [[ -z "$REPLY" ]] && tui.validate.warn "empty title" title
    return 0
}
tui.validate.rule element no_empty_title
```
