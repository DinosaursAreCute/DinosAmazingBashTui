### `tui.sync.plan`

```bash
tui.sync.plan SRC CONFIG
```

Compares the config files of a release (`share/defaults/**`, `share/plugins/*`) with the installed ones, using the checksums in `CONFIG/manifest` as the common base.

**Sets:** arrays of `CONFIG`-relative paths: `TUI_SYNC_ADD` (new), `TUI_SYNC_UPDATE` (you hadn't changed it), `TUI_SYNC_SAME`, `TUI_SYNC_KEEP` (only you changed it), `TUI_SYNC_CONFLICT` (both changed), `TUI_SYNC_REMOVE` (dropped, untouched), `TUI_SYNC_ORPHAN` (dropped, but you changed it).
