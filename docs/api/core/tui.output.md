### `tui.output`

```bash
tui.output PANE [TEXT...]
some_command | tui.output PANE
```

Replaces the pane's content with text, or with stdin when no `TEXT` is given.

**Parameters**

- `TEXT...`: joined with spaces, then split on newlines. ANSI escapes are kept.

**Notes**

- The repaint is queued and coalesced with other changes in the same frame.
- `PANE` must be a valid bash identifier (letters, digits, `_`): the content is stored in a variable named after it.
- Reading stdin (`cmd | tui.output`) costs a pipeline fork; for text updated in a loop use [`tui.set_text`](/api/core/tui.set_text.html).
- Don't mix `tui.output` and `tui.set_text` on the same pane: `tui.set_text` skips text it thinks is already shown.

**Example**

```bash
tui.output log "line one"
tui.output log "$(ls -la)"
df -h | tui.output disk
```

**See also:** [`tui.output_append`](/api/core/tui.output_append.html), [`tui.pane_scroll`](/api/core/tui.pane_scroll.html)
