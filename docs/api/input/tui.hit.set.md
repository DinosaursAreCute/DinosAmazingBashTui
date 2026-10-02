### `tui.hit.set`

```bash
tui.hit.set ID hit_pad|hitbox VALUE
```

Widens the area of a widget that counts as a mouse hit. The same names work as markup attributes on every widget tag.

**Parameters**

- `hit_pad`: `"N"` adds N cells on every side, `"V H"` adds V rows above and below and H columns left and right. Clamped to the widget's pane.
- `hitbox`: `"DY DX H W"` adds one rectangle, given as offsets from the widget's top-left corner and then its height and width.

**Returns:** `1` for any other attribute name.

**Notes**

- The widget's own area always wins over a neighbour's padded area.
- A hit in the extra area reports the zone kind `hitbox` ([`TUI_EVENT_ZONE`](/api/core.html#event-and-result-variables)) and still resolves to the widget, so clicks and hover act as if the widget itself was hit.
- Other zone kinds the mouse can report, in priority order: `scrollbar` (a 3-cell-wide strip over the 1-cell drawn bar, clamped to the pane; 3 rows high for a horizontal bar), `title` (a framed pane's title on its top border), `divider`, `handle` and `chevron` (drawn by resizable and collapsible panes), `widget`, `hitbox`. Anything else resolves to the pane only.

**Example**

```xml
<button id="close" pane="bar" row="0" hit_pad="1" text="x"/>
<button id="tiny" pane="bar" row="1" hitbox="-1 -2 3 8" text="."/>
```

**See also:** [`tui.focus.set`](/api/input/tui.focus.set.html), [`tui.action.click`](/api/input/tui.action.click.html)
