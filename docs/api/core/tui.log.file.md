### `tui.log.file`

```bash
tui.log.file
```

Prints the path [`tui.log`](/api/core/tui.log.html) writes to today.

**Output:** e.g. `/home/me/.config/DABT/apps/my_app/logs/2026-09-24_my_app.log`.

**Notes**

- The file may not exist yet: it is created by the first log line.

**Example**

```bash
tui.view "Log" "$(tail -n 200 "$(tui.log.file)" 2>/dev/null)"
```
