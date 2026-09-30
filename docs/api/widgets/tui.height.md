### `tui.height`

```bash
tui.height WIDGET [SPEC]
```

Gets or sets the explicit height of a widget.

**Parameters**

- `SPEC`: a 2A unit-token size. Omit to get the current value. Default: `auto`.

**Notes**

- `SPEC` can be a number of cells, `%`, `clamp(...)`, or `auto`/`fill`/`fr` which resolve to the widget's default fill size.
- The widget's default fill size is resolved through layout paths panes use.
- Applied before `min_*`/`max_*` clamp further.
- While the app runs, call [`tui.relayout`](/api/core/tui.relayout.html) to apply it.

**See also:** [`tui.width`](/api/widgets/tui.width.html)
