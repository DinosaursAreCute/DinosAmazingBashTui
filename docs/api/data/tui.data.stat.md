### `tui.data.stat`

```bash
tui.data.stat NAME COL FN [VAR]
```

Computes `sum`, `min`, `max`, `avg` or `count` over the numeric cells of a column and prints it, or stores it in `VAR`.

**Notes**

- Numbers may have decimals (`12.5`); they are summed in thousandths, so there is no fork and no floating point. `avg` keeps three decimals.
- Cells that are not numbers are skipped.

**Returns:** `1` for an unknown dataset, column or function, and for `min`, `max` and `avg` of no numbers (the result is then empty). `sum` and `count` of nothing are `0`.

**Example**

```bash
tui.data.stat latency ms avg avg_ms
```
