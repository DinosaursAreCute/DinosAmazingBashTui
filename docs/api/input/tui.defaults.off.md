### `tui.defaults.off`

```bash
tui.defaults.off GROUP... [--page]
```

Switches groups of default bindings off.

**Parameters**

- `GROUP`: `click`, `focus`, `help`, `pages`, `palette`, `pane`, `paste`, `quit`, `scroll`, `wheel` (see [`tui.defaults.list`](/api/input/tui.defaults.list.html)).
- `--page`: only until the page changes. `<tui defaults="-quit,-scroll">` does this.

**Notes**

- Without `--page` it lasts for the run. To persist it, set the `defaults.off` config key.

**Example**

```bash
tui.defaults.off quit          # this app handles q itself
```
