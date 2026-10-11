### `tui.collapsed`

```bash
tui.collapsed PANE
```

Reports whether a pane is collapsed.

**Parameters**

- `PANE` - pane id.

**Returns:** `0` while `PANE` is collapsed, `1` otherwise (also for a pane that is not collapsible).

**Notes**

- Reads `_TUI_P_COLLAPSED[PANE]`, the one place the state is kept.

**See also:** [`tui.collapse`](/api/core/tui.collapse.html)
