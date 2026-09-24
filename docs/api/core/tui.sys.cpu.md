### `tui.sys.cpu`

```bash
tui.sys.cpu
```

Samples CPU usage since the previous call, fork-free.

**Sets:** `TUI_SYS_CPU` (integer percent).

**Returns:** `1` when `/proc/stat` can't be read.

**Notes**

- The first call measures since boot. Call it once to prime, then read it on a timer.
- Linux only.
