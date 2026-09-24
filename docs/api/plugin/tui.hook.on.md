### `tui.hook.on`

```bash
tui.hook.on EVENT FN
```

Registers `FN` to run when the framework fires `EVENT`.

**Events**

- `init` (after `tui.init`), `ready` (before the first frame), `page FILE` (after every page switch), `resize ROWS COLS`, `quit` (`tui.stop`), `exit` (terminal being restored: give back terminal settings and files here), `plugin_enabled NAME`, `plugin_disabled NAME`.
- `key NAME`: before bindings; a handler that returns `0` consumes the key.

**Notes**

- Adding the same `FN` twice for one event is a no-op. Handlers run in registration order.
- Available to apps too, not only plugins.

**Example**

```bash
on_page() { tui.log "visited $1"; }
tui.hook.on page on_page
```
