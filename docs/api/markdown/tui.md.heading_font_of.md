### `tui.md.heading_font_of`

```bash
tui.md.heading_font_of LEVEL VAR
```

Stores in `VAR` the font name of heading level `LEVEL`, or `style` when that level has no font.

**Parameters**

- `LEVEL`: heading level `1` to `6`.
- `VAR`: the name of the variable that receives the font name.

**Example**

```bash
tui.md.heading_font_of 1 font    # font=block5 with the defaults
```
