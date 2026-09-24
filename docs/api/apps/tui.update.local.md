### `tui.update.local`

```bash
tui.update.local PATH DIR
```

Prepares a local update source in `DIR/src` from a release folder, a `.tar.gz`, or a `.dapk` package (verified first). Sets `TUI_UPDATE_SRC_KIND` (`folder`, `archive`, `dapk`).

**Notes**

- For a `.dapk`, `TUI_UPDATE_LOCAL_WORK` names a work folder to delete afterwards.
