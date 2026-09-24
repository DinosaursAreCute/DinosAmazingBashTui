### `tui.install.run`

```bash
tui.install.run SRC PREFIX CONFIG [--policy override|skip|new] [--bindir DIR | --no-link] [--dry-run] [--resolver FN]
```

Installs DABT from a release folder: copies the program to `PREFIX`, the defaults and plugins into `CONFIG`, and links `dabt` into the bin folder. `install.sh` calls it.

**Returns:** `0` done, `1` failed, `2` `SRC` is not a valid release.

**Sets:** `TUI_INSTALL_LOG` (lines), and the plan arrays of [`tui.sync.plan`](/api/apps/tui.sync.plan.html).

**Notes**

- Config files you changed are handled by the conflict policy; see [`tui.sync.apply`](/api/apps/tui.sync.apply.html).
- When `CONFIG` is not the default, `PREFIX/etc/dabt.env` records it so the program can find it.
