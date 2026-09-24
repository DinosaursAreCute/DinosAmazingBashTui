### `tui.get.class.style`

```bash
tui.get.class.style CLASS FIELD [STATE]
```

Prints one field of a theme class, without a pane or widget.

**Parameters**

- `CLASS`: class name without the dot.
- `FIELD`: `fg`, `bg` or `mods`.
- `STATE`: `normal` (default) or a pseudo-state such as `focus`; falls back to the plain class.

**Returns:** `2` for an invalid `FIELD`.

**Example**

```bash
accent=$(tui.get.class.style brand fg)
```

**See also:** [`tui.class.style`](/api/style/tui.class.style.html) (fork-free)
