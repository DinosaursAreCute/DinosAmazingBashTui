### `tui.load_cached`

```bash
tui.load_cached FILE
```

Like [`tui.load`](/api/markup/tui.load.html), but replays the page from its recorded call log when it is cached and unchanged, and records it otherwise.

**Notes**

- "Unchanged" means the page and every `<include>` have the mtimes they had when recorded. Callback scripts are re-sourced on every load, so edits to them apply without invalidating the cache.
- `on_visit` is never recorded: it runs fresh every time.
