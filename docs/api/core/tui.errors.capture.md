### `tui.errors.capture`

```bash
tui.errors.capture on|off
```

Sends the process's standard error to a file that the tick loop reads, so nothing a command or bash itself complains about (`file: line 12: x: bad array subscript`) is drawn over the screen. `tui.init` turns it on and `tui.cleanup` turns it off.

**What happens to an error**

- It is written to the log at level `error` with where it happened, the key and action being handled, the page and the focus.
- It is shown once as an error notification (at most one a second), with `(see the log)`.
- The same message again is only counted and logged again at the 10th, 100th and 1000th time.
- When the app quits, the terminal gets one line: how many errors were logged and where.

**Notes**

- `TUI_ERR_TRACE=1` also traces every command (slow) so each error carries the call stack of the command that failed: `stack: inner < mid < outer @ file:line`.
- `TUI_ERR_CAPTURE=0` leaves stderr alone, for debugging the framework itself.

**Example**

```bash
TUI_ERR_TRACE=1 ./my_app.sh   # then: tail the log for "stack:" lines
```
