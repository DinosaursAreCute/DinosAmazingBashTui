### `tui.debug.segment`

```bash
tui.debug.segment ID FN [left|right]
```

Registers a segment of the debug strip; `FN` sets `_DBG_SEG` to its text, and an empty text hides it.

**Parameters**

- `ID` - segment name; registering the same ID again replaces it.
- `FN` - called on every strip repaint, so it must not fork.
- `left|right` - the side of the strip, default left.

**Example**

```bash
_seg_jobs() { _DBG_SEG="jobs ${#_MY_JOBS[@]}"; }
tui.debug.segment jobs _seg_jobs left
```
