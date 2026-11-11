### `tui.cache.load_dir`

```bash
tui.cache.load_dir DIR
```

Reads pages written by [`tui.cache.dump_dir`](/api/markup/tui.cache.dump_dir.html) and drops every entry that is no longer valid.

**Notes**

- A missing `DIR` is not an error.
- A file that was not written whole is skipped. The files of the older layout (twelve per page) are deleted the first time they are seen.
