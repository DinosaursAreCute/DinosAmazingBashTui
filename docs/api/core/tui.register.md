### `tui.register`

```bash
tui.register KIND NAME FN...
```

Registers one or more handlers `FN` for `NAME` under `KIND`.

**Parameters**

- `KIND` - `tag`, `widget`, `layout`, `validator`, `pseudo`, `expr`, `hook` or `style`.
- `NAME` - the tag/widget type/class name the handler is for.

**Notes**

- A later registration for the same `KIND`/`NAME` is appended, not replaced - read [`tui.registered`](tui.registered.md)'s last word for "last wins", or iterate the whole list for handlers that all run (hooks).
- Made while `$_TUI_REGISTRY_CURRENT_PLUGIN` is set, a registration is attributed to that plugin, so disabling it can remove exactly what it added.
