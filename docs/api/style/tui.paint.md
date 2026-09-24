### `tui.paint`

```bash
tui.paint ID TEXT [STATE]
```

Prints `TEXT` in the style of a widget or pane, followed by a reset. No newline.

**Example**

```bash
tui.output log "$(tui.paint log "ERROR" title) disk full"
```
