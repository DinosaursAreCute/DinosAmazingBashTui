### `tui.reset_ui`

```bash
tui.reset_ui
```

Clears the whole UI and leaves an empty full-screen `root` pane. [`tui.goto`](/api/markup/tui.goto.html) calls it.

**Notes**

- Removes panes, widgets, pane output, styles, timers, watches, `tui.exec` instances, the modal, dialogs, the footer and page-scoped bindings.
- Keeps tick listeners, overlays, toasts, the theme class table, app-wide bindings and settings.
- Clears the screen immediately.
