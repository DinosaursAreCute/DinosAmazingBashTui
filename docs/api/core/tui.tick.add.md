### `tui.tick.add`

```bash
tui.tick.add FN
```

Registers `FN` to run once per main-loop iteration.

**Parameters**

- `FN`: function name, called with no arguments.

**Notes**

- Adding the same `FN` twice is a no-op.
- Listeners survive page changes. Remove page-specific listeners with [`tui.tick.remove`](/api/core/tui.tick.remove.html), or use [`tui.every`](/api/core/tui.every.html), which is cleared on page change.
- While any listener exists the loop polls input every 0.05 s instead of 0.2 s, so an idle app stays cheap only when nothing is registered.
- Never assign `_TUI_TICK_FN` for this: it is a single slot, and overwriting it stops other tick users such as `tui.exec`.
- A listener registered while a plugin loads is removed when that plugin is disabled.

**See also:** [`tui.every`](/api/core/tui.every.html)
