### `tui.config.stage`

```bash
tui.config.stage KEY [VALUE]
```

Changes a setting in memory only, so a control that changes it many times a second does not write the file each time. A missing `VALUE` removes the key.

**Notes**

- [`tui.config.get`](tui.config.get.md) sees the new value at once. Call [`tui.config.flush`](tui.config.flush.md) when the changes settle.
- [`tui.config.set`](tui.config.set.md) still writes immediately.

**Example**

```bash
tui.config.stage glyph.progress.fill "●"
tui.after 0.4 save_settings   # save_settings calls tui.config.flush
```
