### `tui.load`

```bash
tui.load FILE
```

Parses a markup page and builds its panes and widgets through `tui.*` calls. Nothing is drawn.

**Returns:** `1` and a message on stderr when `FILE` can't be read.

**Notes**

- Loads the framework's default theme first, then the page's `<theme>` files.
- Does not validate. [`tui.start`](/api/core/tui.start.html) validates before loading; call [`tui.validate.files`](/api/markup/tui.validate.files.html) yourself when loading pages another way.
- Does not use the page cache and does not reset the current UI; use [`tui.goto`](/api/markup/tui.goto.html) to switch pages.
