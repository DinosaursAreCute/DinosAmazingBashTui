### `tui.log.level`

```bash
tui.log.level [NAME]
```

Prints the log level, or sets it. Lines below the level are not written.

**Parameters**

- `NAME`: `debug`, `info`, `warn`, `error` or `off`. Without it the current level is printed.

**Output:** the current level when called without `NAME`. An unknown `NAME` prints the valid names to stderr, returns 1 and keeps the old level.

**Notes**

- The start-up value is `TUI_LOG_LEVEL` (default `info`, in `tui_configuration.sh`). Change it later with this function: assigning `TUI_LOG_LEVEL` after `tui.sh` is loaded has no effect.
- `debug` logs every page-build step: thousands of lines on a first launch and about 12 ms per page build. Use it while developing; leave it at `info` otherwise.
- A dropped line costs one function call and one comparison. Nothing is formatted or written, and the log folder is not even created.

**Example**

```bash
tui.log.level debug     # while chasing a page-build problem
tui.log.level info
```

**See also:** [`tui.log`](/api/core/tui.log.html), [`tui.log.file`](/api/core/tui.log.file.html)
