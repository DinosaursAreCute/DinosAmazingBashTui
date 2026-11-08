### `tui.glyph.available`

```bash
tui.glyph.available TYPE KEY
```

Lists the glyphs the Settings page offers for a slot, without a subshell. Every slot of a group gets the same list, so a checked and an unchecked mark are picked from one set.

**Sets:** `TUI_GLYPHS` (array; empty when the slot has no entry).

**Notes**

- The lists live in one file, `glyphs/available.txt` of the defaults directory: an `@group slot slot ...` line, then the glyphs of that group. Add a glyph there and every slot of the group offers it.
- It is read once per process. The words `none` (a blank bracket) and `space` (a blank cell) stand for glyphs that cannot be written in the list.

**Example**

```bash
tui.glyph.available checkbox on
printf '%s\n' "${TUI_GLYPHS[@]}"
```
