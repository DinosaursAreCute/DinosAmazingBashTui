### `tui.md.render`

```bash
tui.md.render TEXT WIDTH
```

Renders Markdown `TEXT` into rows of at most `WIDTH` cells.

**Parameters**

- `TEXT`: the Markdown source.
- `WIDTH`: the row width in cells. Values below 1 are treated as 1.

**Results**

- `TUI_MD_ROWS`: array with one styled row per terminal row. Every row starts and ends in the reset state.
- `TUI_MD_MAP`: source line (1-based) of each row. Blank separator rows map to the blank line before the next block.
- `TUI_MD_LINK_URLS` and `TUI_MD_LINK_TEXTS`: the links, in document order.
- `TUI_MD_LINK_ROWS`: the row of each link, in the same order.
- `TUI_MD_HEADS`: one `LEVEL|TITLE|FIRST_ROW|LAST_ROW|LINE` entry per heading.
- `TUI_MD_ANCHORS`: maps the GitHub-style slug of each heading to its row.

**Notes**

- Supported: ATX headings (`#` to `######`), setext headings (`===` and `---` underlines), paragraphs with soft and hard breaks (two trailing spaces or a backslash), block quotes (nested), bullet and ordered lists (nested, tight or loose), task lists (`- [ ]` and `- [x]`), fenced code (```` ``` ```` or `~~~`, clipped rather than wrapped, padded to `WIDTH`), indented code, thematic breaks, **bold**, *italic*, ***both***, ~~strike~~, `code`, `[text](url "title")` links, `<autolinks>`, reference links `[text][ref]` with `[ref]: url` definitions, backslash escapes, images as placeholders (see [`tui.md.images`](/api/markdown/tui.md.images.html)), pipe tables (see [`tui.md.tables`](/api/markdown/tui.md.tables.html)) and a small HTML subset: `<br>`, `<img>`, `<a>`, `<b>`, `<i>`, `<code>`, `<s>`, `<hr>`, `<h1>` to `<h6>` and comments. Other tags are dropped and their text is kept.
- Not supported: raw HTML beyond that subset, math, footnotes.
- Wide characters (CJK, emoji) count two cells under a UTF-8 locale.
- Control bytes and foreign escape sequences are removed from the input.
- Containers (quote, list) need a few cells more than their prefix.
- Text longer than `TUI_MD_MAX_BYTES` (default 262144) skips inline parsing and sets `TUI_MD_DEGRADED=1`.
- `TUI_MD_LINK_URL` selects how links show their target: `inline` (default, `text (url)`) or `hidden`.

**Example**

```bash
tui.md.render "$(<README.md)" 80
printf '%s\n' "${TUI_MD_ROWS[@]}"
```

**See also:** [`tui.md.style`](/api/markdown/tui.md.style.html), [`tui.md.row_for_line`](/api/markdown/tui.md.row_for_line.html), [`tui.md.line_for_row`](/api/markdown/tui.md.line_for_row.html)
