### `tui.after`

```bash
tui.after SEC FN [ID]
```

Calls `FN ID` once, `SEC` seconds from now.

**Parameters**

- As [`tui.every`](/api/core/tui.every.html).

**Notes**

- The timer is removed before `FN` runs, so `FN` may schedule itself again with the same `ID`.
- Cancelled by page change like every timer.

**Example**

```bash
tui.notify "Saved" success
tui.after 3 clear_status
```
