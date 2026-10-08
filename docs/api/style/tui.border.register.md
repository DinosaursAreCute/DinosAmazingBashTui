### `tui.border.register`

```bash
tui.border.register NAME TL TR BL BR HZ VT [CAP_L CAP_R]
```

Adds a border style, usable as `border="NAME"` (and `divider="NAME"`) in markup.

**Parameters**

- `TL TR BL BR`: the four corners. `HZ`, `VT`: the horizontal and vertical edge. One cell each.
- `CAP_L CAP_R`: the glyphs either side of a pane title, which the built-in styles draw as spaces. `┐` and `┌` give btop's look: `┌─┐title┌────┐`. Default: a space each.

**Returns:** `1` with fewer than seven arguments.

**Notes**

- Call it before the page is validated (before `tui.start`), or the validator rejects `border="NAME"`.
- Junctions where panes share an edge are drawn as `single`.

**Example**

```bash
tui.border.register rounded ╭ ╮ ╰ ╯ ─ │
tui.border.register btop ┌ ┐ └ ┘ ─ │ ┐ ┌
```
