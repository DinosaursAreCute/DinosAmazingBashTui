### `tui.monitor`

```bash
tui.monitor PANE [SEC] [ID]
```

Shows a ready-made system dashboard in a pane: CPU, memory and swap gauges, a CPU history sparkline, memory in MB, load average and uptime.

**Parameters**

- `SEC`: refresh interval. Default: `1`.
- `ID`: timer id. Default: `monitor_PANE`.

**Notes**

- Linux only: reads `/proc`.
- Gauges size themselves to the pane width.
