### `tui.data.new`

```bash
tui.data.new NAME [--cols "A|B"] [--key COL] [--max N] [--scope page|session|disk]
```

Declares a dataset: a named list of rows that code appends to, changes and removes, and that widgets can show.

**Parameters**

- `NAME`: letters, digits and `_`, not starting with a digit.
- `--cols`: column names separated by `|`. They name columns in the other calls and become a table's header.
- `--key COL`: the column whose value identifies a row. A keyed dataset has at most one row per key, so `tui.data.append` with an existing key replaces that row.
- `--max N`: keep only the newest `N` rows; the oldest row goes when one is added past `N`.
- `--scope`: `page` (dropped when the page is left), `session` (kept for the run, the default) or `disk` (also written to `$TUI_HOME/state/data/NAME`, read here).

**Returns:** `1` for a bad name, option or key column. Declaring a dataset that exists changes nothing, so a page may declare it on every visit.

**Example**

```bash
tui.data.new latency --cols "ms" --max 60
tui.data.new hosts --cols "host|state" --key host
```
