### `tui.scan.run`

```bash
tui.scan.run PATH [DEEP]
```

Security-scans a script or folder for obvious red flags: pipe-to-shell, reverse shells, `rm -rf /`, setuid, secrets, persistence.

**Parameters**

- `DEEP`: `1` also runs Semgrep when installed (or set `DABT_SCAN_SEMGREP=1`). ShellCheck runs whenever it is on `PATH`.

**Sets:** `TUI_SCAN_HIGH`, `TUI_SCAN_WARN` (counts), `TUI_SCAN_REPORT` (text).

**Returns:** always `0`; check the counts.

**Notes**

- Static checks only: obfuscated code is not detected, so a clean report is not a guarantee.
- Not loaded by `tui.sh`; call `tui.require tui_scan` first.
