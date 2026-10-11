### `tui.canvas.fresh`

```bash
tui.canvas.fresh
```

Returns `0` while the last canvas frame (or patch) is still what the screen shows, because nothing else has painted since. Returns `1` otherwise.

**Notes**

- Only then can a patch be drawn over the canvas: after any other paint the cells under it are not known.
