### `tui.init`

```bash
tui.init
```

Takes over the terminal and prepares an empty `root` pane.

**Notes**

- Applies the saved config, switches to raw input (`stty -echo -icanon -isig -ixon -iexten`), enters the alternate screen, hides the cursor, and turns on mouse tracking and bracketed paste.
- Because of `-isig`, `ctrl+c` and `ctrl+z` arrive as keys instead of signals.
- Records the run in `app.meta`, starts enabled plugins and fires the `init` hook.
- [`tui.start`](/api/core/tui.start.html) calls it. Call it yourself only when building the UI in code; pair it with [`tui.run`](/api/core/tui.run.html).

**See also:** [`tui.cleanup`](/api/core/tui.cleanup.html)
