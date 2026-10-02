### `tui.cache.forget`

```bash
tui.cache.forget FILE
```

Drops everything cached for the page `FILE`, so its next visit builds it fresh.

**Parameters**

- `FILE`: the page's absolute path, as the loader keeps it (`$_TUI_MARKUP_FILE` while that page is the current one).

**Notes**

- Once the app has started, cached pages are trusted without checking file times. Use this after something a page depends on changed while the app was running, for example an [addon](/guide/markup.html#addons) file you just wrote, and then [`tui.goto`](/api/markup/tui.goto.html) the page.

**Example**

```bash
cp new_banner.xml "$TUI_APP_CONF/addons/banner.xml"
tui.cache.forget "$_TUI_MARKUP_FILE"
tui.goto home.xml
```

**See also:** [`tui.addon.dir`](/api/core/tui.addon.dir.html)
