### `tui.text.insert`

```bash
tui.text.insert ID TEXT
```

Inserts `TEXT` at the cursor, replacing the selection, as typing would. The change can be undone and calls the `on_change` function.

**Notes**

- In single-line widgets newlines become spaces and control characters are removed. Tabs become four spaces.

**Example**

```bash
tui.text.insert notes "$(date +%F) "
```
