### `tui.md.show_file`

```bash
tui.md.show_file PANE FILE
```

Renders the contents of `FILE` into the scrolling pane `PANE`, as [`tui.md.show`](/api/markdown/tui.md.show.html) does. Returns `1` when `FILE` cannot be read.

**Parameters**

- `PANE`: the ID of a pane with `scroll="v"`.
- `FILE`: the path of the Markdown file.

**Example**

```bash
tui.md.show_file help_pane docs/help.md || tui.set_label status "no help"
```

**See also:** [`tui.md.show`](/api/markdown/tui.md.show.html)
