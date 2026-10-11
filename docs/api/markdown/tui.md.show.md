### `tui.md.show`

```bash
tui.md.show PANE TEXT
```

Renders `TEXT` as Markdown into the scrolling pane `PANE` (`scroll="v"`).

**Parameters**

- `PANE`: the ID of a pane with `scroll="v"`.
- `TEXT`: the Markdown source.

**Notes**

- The text is remembered, and the pane is rendered again when its width changes (resize, first layout, page switch).
- `<markdown pane="ID" src="FILE"/>` in markup does the same with the contents of a file.

**Example**

```bash
tui.md.show help_pane "$(<README.md)"
```

**See also:** [`tui.md.show_file`](/api/markdown/tui.md.show_file.html), [`tui.md.render`](/api/markdown/tui.md.render.html)
