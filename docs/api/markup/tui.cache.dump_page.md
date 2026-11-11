### `tui.cache.dump_page`

```bash
tui.cache.dump_page KEY [DIR]
```

Writes the recorded page `KEY` to `DIR/<fname>.page`, one file holding the whole entry. `DIR` defaults to the disk cache the background pool persists into.

**Notes**

- The file ends with a marker. A writer that stopped halfway leaves none, and `tui.cache.load_dir` ignores a file without it.
- `KEY` must be a page that is in the cache.
