### `tui.cache.warm_with_spinner`

```bash
tui.cache.warm_with_spinner PAGE...
```

Records pages into the cache in a background worker while showing the D.A.B.T logo and a progress bar.

**Notes**

- Used by [`tui.start_cached`](/api/core/tui.start_cached.html) before the app starts. The worker runs with its output discarded; its stderr goes to a temporary folder.
- Loads the recorded pages into this process when done.
