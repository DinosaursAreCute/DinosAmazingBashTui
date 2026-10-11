### `tui.md.on_link`

```bash
tui.md.on_link FN
```

Sets the function that [`tui.md.link_open`](/api/markdown/tui.md.link_open.html) calls first, as `FN URL TEXT PANE`.

**Notes**

- Return `0` from `FN` when it handled the link; any other status falls through to the default behaviour.

**Example**

```bash
tui.md.on_link my_link_handler
```
