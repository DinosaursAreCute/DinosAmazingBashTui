### `tui.md.fold_toggle`

```bash
tui.md.fold_toggle PANE [HEADING]
```

Folds or unfolds the section under a heading of the document shown in `PANE`.

**Parameters**

- `HEADING`: the index of the heading in `TUI_MD_HEADS` order. Default: the heading at the top of the view.

**Notes**

- A folded section shows a `▸ N rows folded` line in its place.

**Example**

```bash
tui.md.fold_toggle docs 2
```
