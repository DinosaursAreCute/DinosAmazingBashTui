### `tui.md.heading_font`

```bash
tui.md.heading_font LEVEL FONT
```

Sets the block font used for heading level `LEVEL` while [`tui.md.fonts`](/api/markdown/tui.md.fonts.html) is on.

**Parameters**

- `LEVEL`: heading level `1` to `6`.
- `FONT`: `block5` (5 rows), `blk3`, `seg3`, `box3` (3 rows), `half2` (2 rows), `style` or `""` for no font at that level: only the style class (bold, underline, color) is applied.

**Returns:** `1` for an unknown level or font; the setting is left unchanged.

**Notes**

- Defaults: level 1 `block5`, level 2 `box3`, the others plain.
- The heading style's underline is dropped on block rows; it would strike through the letters.

**Example**

```bash
tui.md.heading_font 3 seg3   # ### headings in seg3
tui.md.heading_font 1 ""     # # headings stay plain
```
