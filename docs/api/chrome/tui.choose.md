### `tui.choose`

```bash
tui.choose TITLE ON_CHOOSE ITEM... [flags]
```

Shows a list picker. `ON_CHOOSE` is called with the 0-based index and the item text appended.

**Options**

- `--message TEXT`: text above the list.
- `--selected N`: initially selected index.
- `--cancel CMD`: runs on Esc.

**Returns:** `1` when there are no items.

**Notes**

- Keys: arrows, `j`/`k`, PgUp/PgDn, Enter, digits `1`–`9` pick directly. Click and wheel work.

**Example**

```bash
tui.choose "Export as" do_export csv json yaml
do_export() { tui.notify "Exporting as $2 (#$1)"; }
```
