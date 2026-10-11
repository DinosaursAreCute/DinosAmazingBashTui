### `tui.md.fonts`

```bash
tui.md.fonts on|off|toggle
```

Switches headings that have a font (see [`tui.md.heading_font`](/api/markdown/tui.md.heading_font.html)) between block letters (`on`) and plain styled text (`off`, the default).

**Parameters**

- `on|off|toggle`: the setting to select; `toggle` flips it (default).

**Returns:** `1` for an unknown argument.

**Notes**

- Off by default in the library. [`tui.config.apply`](/api/config/tui.config.apply.html) turns them on unless `md.fonts` is set in the config (Settings > Markdown).
- Takes effect on the next [`tui.md.render`](/api/markdown/tui.md.render.html). Presettable with `TUI_MD_FONTS=1`.
- Words are packed into as many banner lines as the width needs. A heading whose single word is wider than the width falls back to plain text.
- Heading text is drawn without its inline markup, in capitals (the banner fonts are upper-case). [`tui.md.style`](/api/markdown/tui.md.style.html) is never affected.
- The first use loads the banner renderer (`terminal_renderer.sh`).

**Example**

```bash
tui.md.fonts on
tui.md.render "# Title" 80    # five block-letter rows
```
