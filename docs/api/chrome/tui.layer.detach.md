### `tui.layer.detach`

```bash
tui.layer.detach PANE
```

Detaches a pane from its horizontal or vertical split, converting it into a floating layer that appears as a window on top of the page. The siblings of the detached pane take the freed space. Runs the `on_detach` callback if defined.

**Parameters**

- `PANE` - pane id. Must be in an `h` (horizontal) or `v` (vertical) split and have `detachable="true"` in the markup.

**Returns:** `1` when the pane is not in an h/v split, already floats, or does not have `detachable="true"`.

**Notes**

- The detached pane floats as a `<window>` with shadow and close button over the place it occupied, inheriting size from its last dimensions.
- With `leave="placeholder"`, an empty placeholder pane keeps the original space; without it, the siblings redistribute the freed space.
- The pane's `on_detach` callback (if defined) is called after detachment. The floating pane can be docked back with [`tui.layer.dock`](tui.layer.dock.md).
- Markup: pane element with `detachable="true"`, optional `dock_group="NAME"`, `leave="placeholder"`, `on_detach="FN"`, `on_dock="FN"`, and `persist="layout"` (to remember detached state across reloads).

**See also:** [`tui.layer.dock`](tui.layer.dock.md)
