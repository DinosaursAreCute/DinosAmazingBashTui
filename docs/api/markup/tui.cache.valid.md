### `tui.cache.valid`

```bash
tui.cache.valid FILE
```

Returns `0` when `FILE` has a recorded page and neither it nor any of its includes changed since, else `1`.

**Notes**

- `FILE` must be the absolute, normalized path used as the cache key.
- Runs one `stat` per dependency file.
