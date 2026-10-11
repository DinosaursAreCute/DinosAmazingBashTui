### `tui.md.style`

```bash
tui.md.style TEXT
```

Styles Markdown `TEXT` for source editors: one row per source line, with every character kept.

**Parameters**

- `TEXT`: the Markdown source.

**Results**

- `TUI_MD_ROWS`: one styled row per source line. Stripping the SGR sequences gives the input back.
- `TUI_MD_MAP`: identity map.

**Notes**

- Delimiters are drawn with the `marker` class. Headings, quotes, list markers, fences, emphasis, code and links are styled.

**See also:** [`tui.md.render`](/api/markdown/tui.md.render.html), [`tui.md.style_set`](/api/markdown/tui.md.style_set.html)
