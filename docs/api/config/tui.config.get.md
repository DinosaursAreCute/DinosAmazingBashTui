### `tui.config.get`

```bash
tui.config.get KEY [DEFAULT [VAR]]
```

Prints the saved value of a setting, or stores it in `VAR`, which costs no subshell.

**Parameters**

- `KEY`: setting name, e.g. `theme` or `my.option`.
- `DEFAULT`: used when `KEY` is not stored. Default: empty.
- `VAR`: variable that receives the value instead of it being printed.

**Output:** the value, without a trailing newline.

**Notes**

- A key stored with an empty value prints the empty value, not `DEFAULT`.
- Reads the in-memory store. The file is read once when the library is sourced; call [`tui.config.load`](/api/config/tui.config.load.html) to pick up outside edits.

**Example**

```bash
tui.config.get my.autosave 1 autosave   # no subshell
if [[ "$(tui.config.get my.autosave 1)" == 1 ]]; then save_now; fi
```

**See also:** [`tui.config.set`](/api/config/tui.config.set.html), [`tui.config.keys`](/api/config/tui.config.keys.html)
