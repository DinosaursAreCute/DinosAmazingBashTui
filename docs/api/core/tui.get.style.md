### `tui.get.style`

```bash
tui.get.style ID FIELD [STATE]
```

Prints one resolved style field of a pane or widget.

**Parameters**

- `FIELD`: `fg`, `bg` or `mods`.
- `STATE`: `normal` (default), `focus`, `border`, `title`, `hover`, `checked`, `unchecked`. A state with no rules falls back to `normal`.

**Returns:** `2` and a message on stderr for any other `FIELD`.

**See also:** [`tui.style.sgr`](/api/style/tui.style.sgr.html) (fork-free), [`tui.get.class.style`](/api/core/tui.get.class.style.html)
