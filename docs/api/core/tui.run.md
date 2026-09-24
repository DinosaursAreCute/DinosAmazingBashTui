### `tui.run`

```bash
tui.run
```

Runs the main loop (input, dispatch, render, ticks) until [`tui.stop`](/api/core/tui.stop.html) is called, then restores the terminal.

**Notes**

- Fires the `ready` hook once, before the first frame.
- Installs `INT`/`TERM` traps (clean up and exit 1) and a `WINCH` trap for resizes.
- Polls input every 0.05 s while tick listeners exist, else every 0.2 s (`TUI_INPUT_POLL_TIMEOUT`, `TUI_INPUT_IDLE_TIMEOUT`).
- Restores the terminal before it returns, so code after `tui.run` prints to the normal screen.

**Example**

```bash
source lib/tui.sh
tui.init
tui.vsplit root top:1 bottom:3
tui.output bottom "hello"
tui.run
```

**See also:** [`tui.start`](/api/core/tui.start.html)
