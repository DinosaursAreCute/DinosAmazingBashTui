### `tui.tabs.compact`

```bash
tui.tabs.compact TABS_ID [true|false]
```

Picks the header style of a tab group. Call it before [`tui.tabs.build`](/api/core/tui.tabs.build.html).

**Parameters**

- `TABS_ID`: the group id passed to `tui.tabs.build`.
- `true` (default): one-row, borderless headers styled with `.tab_header_compact`. `false`: framed headers (`.tab_header`), which need 3 rows.
