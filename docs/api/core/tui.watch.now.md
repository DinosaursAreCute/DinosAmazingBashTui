### `tui.watch.now`

```bash
tui.watch.now ID
```

Restarts a watch so its command runs again right away.

**Returns:** `1` for an unknown id.

**Example**

```bash
on_refresh() { tui.watch.now watch_disk; }
```
