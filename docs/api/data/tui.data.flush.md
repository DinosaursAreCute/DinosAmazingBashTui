### `tui.data.flush`

```bash
tui.data.flush
```

Updates the widgets bound to datasets that changed since the last flush.

**Notes**

- It runs by itself after every callback and on every tick, so most code never calls it. Call it inside a long callback to draw before the callback returns.
- A widget is only redrawn when the text it would show changed.
