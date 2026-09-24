### `tui.update.check`

```bash
tui.update.check
```

Asks GitHub for the latest DABT version.

**Returns:** `0` a newer version is available, `1` up to date, `2` the check failed (reason in `TUI_UPDATE_ERROR`).

**Sets:** `TUI_UPDATE_LATEST`.

**Notes**

- Channel `release` (default) uses the latest GitHub release; `TUI_UPDATE_CHANNEL=dev` uses the current `main` and always offers it.
- Needs `curl` or `wget`. `TUI_UPDATE_REPO`, `TUI_UPDATE_BRANCH`, `TUI_UPDATE_VERSION_URL` and `TUI_UPDATE_ARCHIVE_URL` override the source.
