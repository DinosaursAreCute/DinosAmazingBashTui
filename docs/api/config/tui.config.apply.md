### `tui.config.apply`

```bash
tui.config.apply
```

Applies the stored framework settings to the running framework.

**Notes**

- Called by `tui.init`. Reads `theme`, `defaults.off`, `notify.position`, `notify.seconds`, `input.retain` and `input.coalesce`; other keys are ignored.
- `theme` is applied only when the file it names is readable.
- `defaults.off` only turns groups off. A group missing from the list is not turned back on; use [`tui.defaults.on`](/api/input/tui.defaults.on.html).

**See also:** [`tui.config.set`](/api/config/tui.config.set.html)
