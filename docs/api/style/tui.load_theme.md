### `tui.load_theme`

```bash
tui.load_theme FILE
```

Loads a stylesheet into the class table. `<theme src="…"/>` calls it.

**Returns:** `1` and a message on stderr when `FILE` can't be read or parsed.

**Notes**

- Rules merge into one table: a later file overrides the fields it sets, and nothing is removed. Classes from a theme loaded on an earlier page stay defined.
- Each file is parsed once per process and re-applied from memory until its mtime changes.
- The app-wide overlay from [`tui.theme.set`](/api/style/tui.theme.set.html) is re-applied after every stylesheet, so it always wins.
- Widgets already styled with [`tui.class`](/api/style/tui.class.html) keep their old colors; load themes before applying classes.
- Class names that collide with a widget or pane style are logged as warnings.

**See also:** [`tui.class`](/api/style/tui.class.html)
