### `tui.cache.decode`

```bash
tui.cache.decode FILE BLOB
```

Installs `BLOB` (from `tui.cache.encode`) as `FILE`'s entry in this process's own cache maps (`_TUI_CACHE_SIG`, `_TUI_CACHE_PAGE`, `_TUI_CACHE_SCRIPTS`, `_TUI_CACHE_ON_VISIT`, `_TUI_CACHE_GOTOS`). Does not check `tui.cache.valid`; callers that read a `.snap` file back from disk should check it themselves.

**Example**

```bash
tui.cache.decode "$page" "$(<"$page.snap")"
```
