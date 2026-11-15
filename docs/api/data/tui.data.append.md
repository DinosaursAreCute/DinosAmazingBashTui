### `tui.data.append`

```bash
tui.data.append NAME ROW...
```

Adds rows at the end. A row is its cells separated by `|`.

**Notes**

- In a keyed dataset a row whose key exists replaces that row in place.
- With `--max N` the oldest rows go when there are more than `N`; the others are not moved.
- A cell cannot contain `|`.

**Returns:** `1` for an unknown dataset.

**Example**

```bash
tui.data.append latency 12 15 9
tui.data.append hosts "web1|up" "db1|down"
```
