### `tui.glyph.set`

```bash
tui.glyph.set TYPE KEY GLYPH [VARIANT]
```

Sets a themeable glyph at run time, for apps that let the user pick a look.

**Parameters**

- `TYPE`, `KEY`, `VARIANT` - the slot, as in [`tui.glyph.get`](tui.glyph.get.md).
- `GLYPH` - one visible, single-cell character.

**Returns:** `1` for an unknown slot or an unusable glyph; nothing changes.

**Notes**

- A theme reload clears glyphs set this way. Set them again when your page is shown.
- Repaint afterwards (`tui.relayout PANE`, or `tui.progress.set` for a bar).

**Example**

```bash
tui.glyph.set progress fill "●"
tui.glyph.set progress empty "○"
```
