### `tui.on_resize`

```bash
tui.on_resize
```

Marks the terminal as resized; the main loop re-lays out on its next iteration.

**Notes**

- Installed as the `WINCH` handler by [`tui.run`](/api/core/tui.run.html). You rarely call it yourself.
- A drag-resize is coalesced: the loop waits until no resize arrived for about 40 ms, then lays out once and fires the `resize` hook.
