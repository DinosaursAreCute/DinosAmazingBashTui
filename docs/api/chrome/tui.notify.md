### `tui.notify`

```bash
tui.notify MESSAGE [LEVEL] [SECONDS]
```

Shows a toast notification that disappears on its own.

**Parameters**

- `LEVEL`: `info` (default), `success`, `warn` (or `warning`), `error`. Anything else counts as `info`.
- `SECONDS`: lifetime. Default: [`tui.notify.seconds`](/api/chrome/tui.notify.seconds.html) (5). `0` = until cleared.

**Sets:** `TUI_NOTIFY_ID` to the new toast's id.

**Notes**

- Up to 5 toasts stack; the oldest is dropped. Toasts survive page changes.
- Position: [`tui.notify.position`](/api/chrome/tui.notify.position.html).
- Styled with `.toast`, `.toast_success`, `.toast_warn`, `.toast_error` when the theme defines them.

**Example**

```bash
tui.notify "Report saved" success
tui.notify "Upload failed" error 0; err_toast=$TUI_NOTIFY_ID
```
