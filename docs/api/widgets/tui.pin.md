### `tui.pin`

```bash
tui.pin ID VALUE
```

Pin a widget to the top of its scrolling pane. When `VALUE` is `top`, the widget scrolls with content until it would leave the viewport top, then stays pinned on the first viewport row (sticky header).

**Parameters**

- `ID`: Widget identifier.
- `VALUE`: Pin mode; only `top` is recognized. Other values are ignored.

**Notes**

- Only one pinned widget is stuck at a time. If multiple pinned widgets pass the scroll threshold, the one with the largest row number wins.
- When scrolling back up, an earlier pinned widget's sticky status returns.
- Other widgets that would land on the first viewport row when a pinned widget is stuck are hidden automatically.
- The widget's pane must have vertical scrolling enabled (`scroll="v"` or `scroll="both"`).

**See also:** [`tui.expand`](/api/widgets/tui.expand.html), [`tui.scroll.to`](/api/core/tui.scroll.to.html)
