### `tui.every`

```bash
tui.every SEC FN [ID]
```

Calls `FN` repeatedly on a timer from the main loop.

**Parameters**

- `SEC`: interval in seconds; decimals allowed (`0.25`). Values below `0.05` are raised to `0.05`.
- `FN`: function, called as `FN ID`.
- `ID`: timer id for [`tui.every.cancel`](/api/core/tui.every.cancel.html) and friends. Default: `FN`.

**Notes**

- The first call happens on the next loop iteration, not after `SEC`. Use [`tui.after`](/api/core/tui.after.html) for a delayed start.
- Registering an existing `ID` again replaces that timer and resumes it if paused. Pass distinct IDs to run one function on two timers.
- Timers are removed on page change. Register them again from the page's `on_visit`.
- After a terminal resize every timer runs on the next iteration, so size-dependent output re-fits at once.
- `FN` runs inside the main loop: keep it fork-free ([`tui.set_text`](/api/core/tui.set_text.html), `tui.sys.*`). Slow work belongs in [`tui.watch`](/api/core/tui.watch.html).
- Timers registered while a plugin loads are removed when that plugin is disabled.

**Example**

```bash
refresh_stats() {
    tui.sys.cpu; tui.sys.mem
    tui.set_text stats "CPU ${TUI_SYS_CPU}%  MEM ${TUI_SYS_MEM_PCT}%"
}
tui.every 2 refresh_stats
```

**See also:** [`tui.after`](/api/core/tui.after.html), [`tui.tick.add`](/api/core/tui.tick.add.html), [`tui.watch`](/api/core/tui.watch.html)
