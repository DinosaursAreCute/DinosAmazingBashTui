### `tui.sync.resolve_ui`

```bash
tui.sync.resolve_ui DONE_FN [SRC]
```

Inside the app: asks about each conflict of the current plan in a dialog (override, skip, `.new`, show the differences, same for the rest), then calls `DONE_FN`.

**Notes**

- The answers are in `TUI_SYNC_DECISION`; apply them with `tui.sync.apply SRC CONFIG _tui_sync.decided`.
