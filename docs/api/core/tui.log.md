### `tui.log`

```bash
tui.log MSG [LEVEL]
```

Appends a line to the app's log file. stdout is the screen, so logs go to a file.

**Parameters**

- `MSG`: the message.
- `LEVEL`: free text shown in brackets. Default: `info`.

**Output:** nothing on screen. The file gets `[HH:MM:SS] [LEVEL] MSG`.

**Notes**

- The file is `~/.config/DABT/apps/<TUI_APP_NAME>/logs/<yyyy-mm-dd>_<TUI_APP_NAME>.log` (`dabt` when no app name is set). Set `TUI_LOG_DIR` before sourcing `tui.sh` to use another folder. [`tui.log.file`](/api/core/tui.log.file.html) prints the current path.
- One file per day; an app running past midnight continues in the next day's file.
- Fork-free once the folder exists. A log folder that can't be created or written is ignored silently; logging never fails the caller.
- Logs are never rotated or deleted.

**Example**

```bash
tui.log "export started: $file"
tui.log.warn "config missing, using defaults"
```

**See also:** [`tui.log.debug`](/api/core/tui.log.debug.html), [`tui.log.info`](/api/core/tui.log.info.html), [`tui.log.warn`](/api/core/tui.log.warn.html), [`tui.log.error`](/api/core/tui.log.error.html)
