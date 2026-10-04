### `tui.layer.dock`

```bash
tui.layer.dock LAYER [PANE]
```

Docks a floating pane back into its original split, restoring it to its previous position and size spec. If `PANE` is given, docks the pane as the last child of that split pane instead. Runs the `on_dock` callback if defined.

**Parameters**

- `LAYER` - floating layer id (created by [`tui.layer.detach`](tui.layer.detach.md)).
- `PANE` - (optional) split pane to dock into. If omitted, the layer returns to its original parent and position.

**Returns:** `1` when the layer was not detached, or (with `PANE`) when `PANE` is not in the same `dock_group`.

**Notes**

- A layer can be docked only if it was originally detached from a split with [`tui.layer.detach`](tui.layer.detach.md).
- If a placeholder pane was left behind (created with `leave="placeholder"`), docking restores the original pane to that placeholder's position. Otherwise, the pane becomes the last child of its target.
- When docking into a different pane with `PANE`, both must share the same `dock_group="NAME"` attribute.
- The pane's `on_dock` callback (if defined) is called after docking. The docked pane returns to being a normal split child.

**See also:** [`tui.layer.detach`](tui.layer.detach.md)
