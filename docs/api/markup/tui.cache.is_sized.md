### `tui.cache.is_sized`

```bash
tui.cache.is_sized FILE
```

Returns `0` when the cached geometry of `FILE` was laid out for the current terminal size, else `1`.

**Notes**

- `FILE` must be the absolute, normalized path used as the cache key.
- A replay of a page that is sized needs no relayout. `tui.start_cached` has the background pool rebuild every cached page that is not, so the first visit finds it ready.
- A page cached before the size was recorded is never sized.
