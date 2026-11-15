### `tui.data.has`

```bash
tui.data.has NAME ID
```

Succeeds when a row with that id exists (the key for a keyed dataset, else the 0-based index).

**Example**

```bash
tui.data.has hosts web1 || tui.data.append hosts "web1|up"
```
