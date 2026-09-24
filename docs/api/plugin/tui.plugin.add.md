### `tui.plugin.add`

```bash
tui.plugin.add PATH [SOURCE]
```

Registers one plugin file or folder, disabled.

**Parameters**

- `PATH`: a `NAME.plugin.sh` file or a folder containing `plugin.sh`.
- `SOURCE`: `builtin`, `app` or `user` (default), shown in lists.

**Returns:** `1` when the file can't be read or another plugin already has the name.

**Sets:** `TUI_PLUGIN_NAME` on success, `TUI_PLUGIN_ERROR` on failure.

**Notes**

- Reads only the metadata comments in the first 40 lines (`# plugin:`, `# title:`, `# version:`, `# description:`, `# author:`, `# requires:`, `# default: on|off`). The file is sourced only when enabled.
- The name is lowercased, with characters other than `a-z 0-9 _` turned into `_`.
