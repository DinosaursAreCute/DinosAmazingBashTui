### `tui.cache.deps_of`

```bash
tui.cache.deps_of FILE ARRAY_NAME
```

Appends `FILE` and every file it includes, recursively, to the array named `ARRAY_NAME`, as absolute paths.

**Notes**

- Unreadable files and files already in the array are skipped.

**Example**

```bash
local -a deps=()
tui.cache.deps_of "$page" deps
```
