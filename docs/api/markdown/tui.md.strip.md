### `tui.md.strip`

```bash
tui.md.strip STR [VAR]
```

Removes the SGR (color and attribute) sequences from `STR`, then prints the result or stores it in `VAR`.

**Parameters**

- `STR`: the styled string.
- `VAR`: optional variable name. When given, the result is stored there and nothing is printed. No subshell is used.

**Example**

```bash
tui.md.strip "$line" plain
```
