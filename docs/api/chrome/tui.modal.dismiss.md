### `tui.modal.dismiss`

```bash
tui.modal.dismiss
```

Closes the open modal without running anything, replaying the saved page frame when it still matches the screen.

**Notes**

- Use it for esc and click-outside. It falls back to `tui.modal.close` (a full repaint) when anything but an overlay has painted, restyled or resized since the last full render.
- Do not use it when the close is followed by an action that changes state: the saved frame cannot know about that.
- `TUI_DISMISS_REPLAY=0` turns the replay off.
