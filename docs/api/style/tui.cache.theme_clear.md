### `tui.cache.theme_clear`

```bash
tui.cache.theme_clear
```

Forgets every memoized stylesheet, so the next load parses the files again.

**Notes**

- Only needed when a file changed without a new mtime; normally edits are picked up automatically.
