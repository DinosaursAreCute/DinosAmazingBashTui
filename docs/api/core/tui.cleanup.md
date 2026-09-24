### `tui.cleanup`

```bash
tui.cleanup
```

Restores the terminal: mouse tracking and bracketed paste off, style reset, cursor shown, main screen, unread input drained, original `stty` settings back.

**Notes**

- [`tui.run`](/api/core/tui.run.html) and the signal traps already call it. Call it yourself only when you called [`tui.init`](/api/core/tui.init.html) without `tui.run`.

**See also:** [`tui.init`](/api/core/tui.init.html)
