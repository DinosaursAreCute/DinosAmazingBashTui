### `tui.progress.set`

```bash
tui.progress.set ID VALUE [MAX]
```

Sets a progress bar to `VALUE` out of `MAX` and redraws it.

**Parameters**

- `VALUE`: integer.
- `MAX`: integer. Default: `100`.

**Notes**

- Stored as a whole percent, clamped to 0–100.

**Example**

```bash
tui.progress.set job "$done" "$total"
```
