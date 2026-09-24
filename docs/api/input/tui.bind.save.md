### `tui.bind.save`

```bash
tui.bind.save [FILE]
```

Writes the user bindings (`--user`) to disk; they load automatically on the next start.

**Parameters**

- `FILE`: default [`tui.bind.saved_file`](/api/input/tui.bind.saved_file.html) (`~/.config/DABT/apps/<app>/keybinds.xml`).

**Returns:** `1` and a message on stderr when the file can't be written.

**Notes**

- With no user bindings the file is deleted.
- Saving to another `FILE` does not change which file loads at start.
