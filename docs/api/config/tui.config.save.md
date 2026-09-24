### `tui.config.save`

```bash
tui.config.save
```

Writes the in-memory store to the config file.

**Returns:** `1` when the config directory cannot be created, else `0`.

**Notes**

- Keys are written sorted, as `key=value` lines under a comment header. The write goes to a temporary file that is then moved into place, so a crash never leaves a half-written file.
- An empty store deletes the file instead.
- [`tui.config.set`](/api/config/tui.config.set.html) and [`tui.config.unset`](/api/config/tui.config.unset.html) already call it.

**See also:** [`tui.config.load`](/api/config/tui.config.load.html)
