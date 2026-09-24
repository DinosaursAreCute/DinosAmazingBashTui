### `tui.start_cached`

```bash
tui.start_cached FIRST_PAGE
```

Like [`tui.start`](/api/core/tui.start.html), but first records every page the app can reach into the page cache, so later page switches replay instead of parsing.

**Parameters**

- `FIRST_PAGE`: the page to open. Every `*.xml` next to it and every shipped default page (`share/defaults/pages/`) is warmed too.

**Returns:** as [`tui.start`](/api/core/tui.start.html).

**Notes**

- Files whose name starts with `_` (fragments for `<include>`) are skipped.
- All warmed pages are validated before the terminal is taken over, not only `FIRST_PAGE`.
- Only pages that are missing from the on-disk cache or changed since are re-recorded, behind a progress banner. The cache lives in [`tui.cache.disk_dir`](/api/markup/tui.cache.disk_dir.html).

**See also:** [`tui.cache.warm_with_spinner`](/api/markup/tui.cache.warm_with_spinner.html), [`tui.load_cached`](/api/markup/tui.load_cached.html)
