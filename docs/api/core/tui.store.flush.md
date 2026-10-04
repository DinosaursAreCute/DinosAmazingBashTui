### `tui.store.flush`

```bash
tui.store.flush
```

Writes the disk image of the page-state store to `tui.store.file` now.

**Notes**

- Only the fields of items marked `persist="disk"` are in the file; session state never is.
- The file is data only: the first line is `# dabt-state 1`, then one `PAGE TAB ID TAB FIELD TAB VALUE` line per entry with `\\`, `\t`, `\n` and `\r` escaped. It is read line by line and never sourced.
- The write goes to `store.tmp.PID` (mode `0600`, in a `0700` folder) and is renamed over the old file.
- Pages and app exit write it on their own when something changed; call this to write at a moment of your choosing.

**Returns:** `0` on success, `1` when `TUI_HOME` is unset or the file cannot be written.

**See also:** [`tui.store.file`](/api/core/tui.store.file.html), [`tui.page.reset_all`](/api/core/tui.page.reset_all.html)
