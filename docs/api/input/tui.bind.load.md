### `tui.bind.load`

```bash
tui.bind.load [FILE]
```

Replaces the user bindings with those in `FILE` (default: the saved file) and marks them saved.

**Notes**

- Runs automatically when the library is sourced.
- Commands that are not defined yet are kept and skipped when pressed.
