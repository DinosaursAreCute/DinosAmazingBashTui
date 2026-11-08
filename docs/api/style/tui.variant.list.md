### `tui.variant.list`

```bash
tui.variant.list TYPE
```

Lists the designs the loaded theme defines for one widget type, without a subshell.

**Sets:** `TUI_VARIANTS` (array, sorted; empty when the type has none). The built-in base look, `default`, is not in it.

**Example**

```bash
tui.variant.list progress
printf '%s\n' "${TUI_VARIANTS[@]}"   # ascii dots squares thin
```
