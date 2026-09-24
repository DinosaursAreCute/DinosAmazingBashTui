### `tui.validate.files`

```bash
tui.validate.files PAGE...
```

Validates pages and their includes, replacing any earlier findings.

**Returns:** `1` when any error was found, else `0` (warnings don't count).

**Sets:** `TUI_V_ERRORS`, `TUI_V_WARNINGS`.

**Notes**

- Reports unknown tags, unclosed or mismatched tags, missing and invalid attributes, conflicting attributes, duplicate ids, widgets in missing or split panes, grid cells out of bounds, and missing script/theme/include/page files, each with file, line and column.
- [`tui.start`](/api/core/tui.start.html) and [`tui.start_cached`](/api/core/tui.start_cached.html) run it automatically before the terminal is taken over.

**Example**

```bash
tui.validate.files config/*.xml || { tui.validate.report >&2; exit 1; }
```

**See also:** [`tui.validate.report`](/api/markup/tui.validate.report.html)
