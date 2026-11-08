### `tui.variant.default`

```bash
tui.variant.default TYPE [NAME]
```

Sets the design widgets of one type use when they name no [`variant`](/api/widgets/tui.variant.html) of their own. The Settings page uses it; the choice is stored as `variant.TYPE` in the app's `dabt.conf`.

**Parameters**

- `TYPE` - `progress`, `checkbox`, `select`, `scrollbar` (the list, table and textarea scroll indicator) or `panebar` (the scrollbars of scrolling panes).
- `NAME` - a design the theme defines, or `custom`: the user's own parts set with [`tui.glyph.user`](tui.glyph.user.md). Empty or missing clears it.

**Notes**

- A widget's own `variant=` wins. A name the theme does not define draws the base look.
- Takes effect on the next draw; call `tui.redraw` to repaint at once.

**Example**

```bash
tui.variant.default progress thin
tui.redraw
```
