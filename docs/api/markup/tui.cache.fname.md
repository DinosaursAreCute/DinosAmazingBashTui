### `tui.cache.fname`

```bash
tui.cache.fname FILE
```

The filesystem-safe encoding of a cache key: every `/` becomes `_`. Used to name the files `tui.cache.dump_dir`/`tui.cache.warm_with_spinner`'s worker pool write per page.

**Example**

```bash
local fn
fn="$(tui.cache.fname "$page")"
```
