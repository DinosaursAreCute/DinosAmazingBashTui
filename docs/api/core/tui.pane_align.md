### `tui.pane_align`

```bash
tui.pane_align PANE left|center|right|fill
```

Sets the default horizontal alignment for widgets in the pane.

**Notes**

- A widget's own [`tui.align`](/api/widgets/tui.align.html) wins. Without either, widgets are left-aligned and buttons centered.
- Affects widgets only, not text from [`tui.output`](/api/core/tui.output.html).
