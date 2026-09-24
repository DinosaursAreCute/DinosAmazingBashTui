### `tui.hist.push`

```bash
tui.hist.push NAME VALUE [MAX]
```

Appends a value to a named rolling series, dropping the oldest beyond `MAX`.

**Parameters**

- `VALUE`: one word; values are stored space-separated.
- `MAX`: series length. Default: `60`.

**Example**

```bash
tui.sys.cpu; tui.hist.push cpu "$TUI_SYS_CPU" 120
```

**See also:** [`tui.hist.get`](/api/core/tui.hist.get.html)
