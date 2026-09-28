### `tui.cache.encode`

```bash
tui.cache.encode FILE
```

Everything `tui.cache.record` captured for `FILE` (its signature, its built-state snapshot, the scripts it sourced, its `on_visit` function and its nav-button definitions), packed into one blob a parallel warm-up worker can write to a single file. Pair with `tui.cache.decode` to load it back in another process.

**Notes**

- The blob's five fields are joined with `\x1e` (record separator), a byte that never appears in the fields themselves.
- Used by `tui.cache.warm_with_spinner`'s worker pool for one atomic `FILE.snap` per page, instead of `tui.cache.dump_dir`'s five files per page.

**Example**

```bash
tui.cache.encode "$page" >"$tmp_file"
mv "$tmp_file" "$page.snap"
```
