### `tui.require`

```bash
tui.require LIBRARY
```

Sources an optional bundled library once per process.

**Parameters**

- `LIBRARY`: `terminal_renderer`, `terminal_controls` or `tui_scan`.

**Returns:** `1` and a message on stderr for an unknown name.

**Notes**

- Callback files are re-sourced on every page visit. Use `tui.require` there instead of `source` so a large library is loaded only once.

**Example**

```bash
tui.require terminal_renderer
tui.output stats "$(table_string 'Name|Size' 'a.txt|1k')"
```
