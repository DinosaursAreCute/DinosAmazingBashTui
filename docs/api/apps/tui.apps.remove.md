### `tui.apps.remove`

```bash
tui.apps.remove NAME [--yes] [--purge]
```

Uninstalls an app after running its `uninstall_hook`. Its settings folder is kept unless `--purge` is given; `--yes` skips the confirmation.
