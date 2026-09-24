### `tui.cache.dump_dir`

```bash
tui.cache.dump_dir DIR
```

Writes every recorded page to `DIR`, three files per page (`.key`, `.cache`, `.sig`).

**Notes**

- Creates `DIR`. Existing files for other pages are left alone.
