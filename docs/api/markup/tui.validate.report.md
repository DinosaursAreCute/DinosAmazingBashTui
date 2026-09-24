### `tui.validate.report`

```bash
tui.validate.report
```

Prints every finding, then a `N error(s), M warning(s)` summary. Prints nothing when there are no findings.

**Output:** one line per finding, e.g. `erroneous configuration in config/home.xml line 12 col 5: <button> needs a pane`. Warnings start with `questionable configuration`. Errors are red and warnings yellow when stderr is a terminal.

**Notes**

- Writes to stdout; redirect to stderr yourself: `tui.validate.report >&2`.
