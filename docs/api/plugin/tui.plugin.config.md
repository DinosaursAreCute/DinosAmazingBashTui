### `tui.plugin.config`

```bash
tui.plugin.config NAME KEY [VALUE]
```

Reads or writes a plugin's own saved setting, stored as `plugin.NAME.KEY` in `dabt.conf`.

**Notes**

- With `VALUE`: saves it. Without: prints the stored value (no newline).
- To read with a default, use `tui.config.get plugin.NAME.KEY DEFAULT`; the third argument here always means "set".

**Example**

```bash
interval=$(tui.plugin.config clock interval); interval=${interval:-5}
tui.plugin.config clock interval 10
```
