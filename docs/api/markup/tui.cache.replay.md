### `tui.cache.replay`

```bash
tui.cache.replay FILE
```

Rebuilds a page by replaying its recorded call log. Returns `1` when nothing is recorded for `FILE`.

**Notes**

- Does not check whether the recording is still valid; call [`tui.cache.valid`](/api/markup/tui.cache.valid.html) first.
