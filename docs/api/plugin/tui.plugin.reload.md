### `tui.plugin.reload`

```bash
tui.plugin.reload NAME
```

Re-reads a plugin after its file changed: disables it, drops its `plugin.NAME.*` functions, re-reads the metadata, and enables it again if it was enabled. Returns `1` for an unknown plugin.

**Notes**

- The saved state is not changed.
