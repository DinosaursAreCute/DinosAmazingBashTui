### `tui.table`

```bash
tui.table ID PANE ROW [ACTION] [ROWS]
```

Creates a scrollable table: a header row plus rows of `|`-separated cells, one selectable row at a time.

**Parameters**

- As [`tui.list`](/api/widgets/tui.list.html).

**Example**

```bash
tui.table procs main 0 show_proc
tui.table.set procs "PID|Name|CPU" "1|init|0.0" "42|bash|1.2"
```
