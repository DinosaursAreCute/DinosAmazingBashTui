### `tui.action.contextmenu`

```bash
tui.action.contextmenu
```

Opens the `<contextmenu>` that owns what is under the pointer, at the pointer. Bound to `mouse:right` by default.

**Notes**

- The owner is the widget under the pointer if a menu has `for="#id"` naming it, else the pane the widget sits in, else the parent panes. A menu with a `for` answers only on that widget.
- Another open menu or popup closes first. Does nothing under a modal layer, or when no menu owns the spot.
