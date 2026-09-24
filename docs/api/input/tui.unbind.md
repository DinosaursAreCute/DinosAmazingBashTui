### `tui.unbind`

```bash
tui.unbind KEY [--pane ID] [--user]
```

Removes a code binding, or with `--user` a user binding. The default for `KEY` applies again.

**Notes**

- `--pane` must match the scope the binding was made with.
- Default bindings can't be unbound one by one; switch their group off with [`tui.defaults.off`](/api/input/tui.defaults.off.html) or bind the key to something else.
