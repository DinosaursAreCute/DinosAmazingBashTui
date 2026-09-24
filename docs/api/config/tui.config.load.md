### `tui.config.load`

```bash
tui.config.load
```

Replaces the in-memory store with the contents of the config file.

**Notes**

- Runs automatically when the library is sourced. Call it again only to pick up changes made outside the running app.
- Lines starting with `#` and lines without `=` are skipped. The value is everything after the first `=`.
- A missing file gives an empty store and returns `0`.

**See also:** [`tui.config.save`](/api/config/tui.config.save.html), [`tui.config.apply`](/api/config/tui.config.apply.html)
