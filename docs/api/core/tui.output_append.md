### `tui.output_append`

```bash
tui.output_append PANE [TEXT...]
some_command | tui.output_append PANE
```

Appends lines to the pane's content, from arguments or stdin.

**Notes**

- Content is kept in memory without a limit. For a long-running log, trim it yourself or use [`tui.exec`](/api/core/tui.exec.html).

**See also:** [`tui.output`](/api/core/tui.output.html)
