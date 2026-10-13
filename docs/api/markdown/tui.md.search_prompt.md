### `tui.md.search_prompt`

```bash
tui.md.search_prompt PANE
```

Asks for a search text in a prompt, then runs [`tui.md.search`](tui.md.search.md) on `PANE` with it. An empty text clears the search; the match shown (`3/12`) or `No match` is announced as a notification.

**Example**

```bash
tui.bind alt+s "tui.md.search_prompt docs" --always
```
