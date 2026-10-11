### `tui.md.search`

```bash
tui.md.search PANE TEXT
```

Searches the rendered document in `PANE` for `TEXT`, case-insensitively as plain text.

**Parameters**

- `TEXT`: the text to find; an empty `TEXT` clears the search.

**Returns:** `1` when there is no match.

**Notes**

- Every match is drawn in reverse video and the view jumps to the first one.
- Step through the matches with [`tui.md.search_next`](/api/markdown/tui.md.search_next.html) and [`tui.md.search_prev`](/api/markdown/tui.md.search_prev.html); [`tui.md.search_info`](/api/markdown/tui.md.search_info.html) reports the position.

**Example**

```bash
tui.md.search docs "config key"
```
