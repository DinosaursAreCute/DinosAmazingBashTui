### `tui.glyph.get`

```bash
tui.glyph.get TYPE KEY [VARIANT]
```

Resolves a themeable glyph into `TUI_GLYPH`, without a subshell: the variant's value, else the base type's, else the built-in default.

**Parameters**

- `TYPE`, `KEY` - the slot, e.g. `progress` `fill`. Themes set it with `.progress { fill: "█"; }`.
- `VARIANT` - optional design name, set with `.progress.thin { fill: "━"; }`.

**Notes**

- A glyph is a quoted, single-cell string. Control characters, wide glyphs and `;` are not accepted (an empty string only for the bracket slots below); the rule is skipped and a warning is logged.
- Slots: `progress.fill` `progress.empty`; `checkbox.left` `checkbox.on` `checkbox.off` `checkbox.right`; `select.left` `select.arrow` `select.right`; `scrollbar.thumb` `scrollbar.track`; `panebar.vthumb` `panebar.vtrack` `panebar.hthumb` `panebar.htrack` (the vertical and horizontal scrollbars of scrolling panes; a blank thumb is drawn reversed).
- The `left` and `right` slots may be set to `""` for a look without brackets. Widgets pick their variant with [`tui.variant`](/api/widgets/tui.variant.html).

**Sets:** `TUI_GLYPH`

**Example**

```bash
tui.glyph.get progress fill thin
printf '%s' "$TUI_GLYPH"
```
