### `tui.page.rebuild`

```bash
tui.page.rebuild [--delay MS] [--label TEXT] FILE
```

Builds the page `FILE` again in the background and shows it when it is complete. The options are those of [`tui.job.run`](/api/core/tui.job.run.html), which runs it.

**Parameters**

- `FILE`: a page file. Use `$_TUI_MARKUP_FILE` for the page on screen.

**Returns:** `1` when `FILE` cannot be read.

**Notes**

- The build is the same headless build the start-up warm-up does. Its result becomes the cached page, and if `FILE` is still the page on screen the app goes to it with a single redraw. The focused widget stays focused when it still exists.
- If the user has moved to another page in the meantime, nothing is drawn; the next visit of `FILE` uses the new build.
- A failed build keeps the old page and shows the reason in a toast.
- It rebuilds the whole page, so it takes as long as a cold build. To apply an [addon](/guide/markup.html#addons) file you just wrote, use [`tui.page.refresh`](/api/core/tui.page.refresh.html), which rebuilds only what changed and falls back to this function when it cannot.
- `--quiet` only refreshes the cached copy of the page: no spinner, nothing drawn.

**Example**

```bash
regenerate_includes                                        # a file the page includes changed on disk
tui.page.rebuild --label "Updating page..." "$_TUI_MARKUP_FILE"
```

**See also:** [`tui.cache.forget`](/api/core/tui.cache.forget.html), [`tui.addon.dir`](/api/core/tui.addon.dir.html)
