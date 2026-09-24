### `tui.sys.mem`

```bash
tui.sys.mem
```

Samples memory and swap usage from `/proc/meminfo`, fork-free.

**Sets:** `TUI_SYS_MEM_PCT`, `TUI_SYS_MEM_USED_MB`, `TUI_SYS_MEM_TOTAL_MB`, `TUI_SYS_SWAP_PCT`.

**Notes**

- "Used" is total minus available, so file cache does not count as used. Linux only.
