### `tui.data.sort`

```bash
tui.data.sort NAME COL [--desc] [--num]
```

Sorts the rows in place. The sort is stable.

**Parameters**

- `--desc`: largest first.
- `--num`: compare the cells as numbers (decimals allowed) instead of as text.

**Notes**

- Text is compared with the current locale, as `[[ a < b ]]` does.

**Returns:** `1` for an unknown dataset, column or option.

**Example**

```bash
tui.data.sort procs cpu --num --desc
```
