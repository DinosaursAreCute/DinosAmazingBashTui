### `tui.text.mode`

```bash
tui.text.mode ID markdown|plain
```

Styles a textarea's source as Markdown while typing (headings, emphasis, code, links, quotes, lists, fences; characters, columns, cursor and selection unchanged, only the styling differs), or back to plain.

**Notes**

- Returns `1` for non-textarea widgets or an unknown mode.
- Same as `<textarea mode="markdown">`.

**Example**

```bash
tui.text.mode notes markdown
```
