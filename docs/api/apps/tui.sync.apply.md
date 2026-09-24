### `tui.sync.apply`

```bash
tui.sync.apply SRC CONFIG [RESOLVER]
```

Applies the plan from [`tui.sync.plan`](/api/apps/tui.sync.plan.html) and rewrites `CONFIG/manifest`.

**Parameters**

- `RESOLVER`: function called as `RESOLVER REL` for each conflict; prints `override` (take the release's file), `skip` (keep yours) or `new` (write the release's as `FILE.new`). Without it, `TUI_SYNC_POLICY` decides (default `new`).

**Sets:** `TUI_SYNC_BACKUP` (the backup folder), `TUI_SYNC_COUNT` (counts per action).

**Notes**

- Every file it replaces is copied to `CONFIG/backups/STAMP/` first.
