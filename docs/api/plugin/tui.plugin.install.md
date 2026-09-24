### `tui.plugin.install`

```bash
tui.plugin.install PATH [--force] [--strict] [--no-scan]
```

Security-scans a plugin, copies it into `~/.config/DABT/plugins` and registers it, disabled.

**Options**

- `--force`: replace an installed plugin of the same name; with `--strict`, install despite high-risk findings.
- `--strict`: refuse when the scan finds high-risk issues.
- `--no-scan`: skip the scan.

**Returns:** `1` on failure, with the reason in `TUI_PLUGIN_ERROR`.

**Sets:** `TUI_PLUGIN_WARNING` to a one-line scan summary when there were findings; the full report is in `TUI_SCAN_REPORT`.

**Notes**

- Plugins run in the app's shell with its permissions. The scan flags risky patterns; it is not a sandbox.

**See also:** [`tui.scan.run`](/api/apps/tui.scan.run.html)
