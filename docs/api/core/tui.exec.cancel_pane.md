### `tui.exec.cancel_pane`

```bash
tui.exec.cancel_pane PANE
```

Kills and dismisses every `tui.exec` instance targeting `PANE`, running or finished, and empties the pane.

**Example**

```bash
on_visit_shell() {
    tui.exec.cancel_pane term      # one shell per visit, not one more per visit
    tui.exec "bash -i" term
}
```
