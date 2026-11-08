### `tui.glyph.user`

```bash
tui.glyph.user TYPE KEY [GLYPH]
```

Sets one part of the user's own design, `custom`, and keeps it across theme changes. The Settings page uses it; the choice is stored as `glyph.TYPE.KEY` in the app's `dabt.conf`.

**Parameters**

- `TYPE`, `KEY` - the slot, as in [`tui.glyph.get`](tui.glyph.get.md).
- `GLYPH` - one visible, single-cell character (a space is allowed). Missing removes the part. Empty removes it too, except for the bracket slots (`checkbox` and `select` `left` / `right`), where it blanks them.

**Returns:** `1` for an unknown slot or an unusable glyph; nothing changes.

**Notes**

- The parts only show on widgets whose design is `custom`: set it with [`tui.variant.default`](tui.variant.default.md) or `variant="custom"`. Every other design keeps the theme's glyphs, so it is always clear which one is in force. A part left out of `custom` comes from the theme's base look.
- Unlike [`tui.glyph.set`](tui.glyph.set.md), it is not cleared by a theme reload.

**Example**

```bash
tui.glyph.user progress fill "●"
```
