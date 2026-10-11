### `tui.md.breaks`

```bash
tui.md.breaks on|off|toggle
```

Chooses whether a single newline inside a paragraph breaks the line (`on`) or joins the lines with a space (`off`, the default).

**Parameters**

- `on|off|toggle`: the setting to select; `toggle` flips it (default).

**Returns:** `1` for an unknown argument.

**Notes**

- Takes effect on the next [`tui.md.render`](/api/markdown/tui.md.render.html); re-render what is on screen after changing it.
- A blank line always separates paragraphs. The setting also applies to lines inside list items and quotes, and can be preset with `TUI_MD_BREAKS=1`.

**Example**

```bash
tui.md.breaks on
tui.md.render $'one\ntwo' 40   # two rows: "one", "two"
```
