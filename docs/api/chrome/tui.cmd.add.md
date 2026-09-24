### `tui.cmd.add`

```bash
tui.cmd.add ID TITLE ACTION [--group G] [--desc TEXT] [--when FN] [--key KEY]
```

Registers a command in the command palette.

**Parameters**

- `ID`: unique command id. Adding an existing `ID` replaces it.
- `TITLE`: what the palette shows and searches.
- `ACTION`: function plus arguments, chained with `;` if needed. Same rules as a [`tui.bind`](/api/input/tui.bind.html) command.

**Options**

- `--group G`: heading the command is listed under.
- `--desc TEXT`: second line in the palette.
- `--when FN`: the command is listed only while `FN` returns `0`.
- `--key KEY`: also binds `KEY` to the command; the palette shows it as the hint.

**Returns:** `1` when `ID`, `TITLE` or `ACTION` is missing.

**Notes**

- Commands added while a plugin loads are removed when that plugin is disabled, and show the plugin's name as their hint.

**Example**

```bash
tui.cmd.add export "Export report" on_export --group App --desc "Write report.csv" --key ctrl+e
```
