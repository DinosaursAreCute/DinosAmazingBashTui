### `tui.md.tables`

```bash
tui.md.tables grid|rounded|plain|stacked
```

Chooses how pipe tables are drawn.

**Parameters**

- `grid|rounded|plain|stacked`: `grid` draws box lines, `rounded` draws the box with round corners, `plain` has no frame and a rule under the header, `stacked` writes each row as `Header: value` lines.

**Returns:** `1` for another name.

**Notes**

- `stacked` is also used when the pane is too narrow for the table.
- Persisted as `md.tables` in the config.

**Example**

```bash
tui.md.tables plain
```
