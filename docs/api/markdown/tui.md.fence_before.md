### `tui.md.fence_before`

```bash
tui.md.fence_before TEXT TOP VAR
```

Stores in `VAR` the code-fence state (`""` or `CHAR:LEN`) in force at source line `TOP` (0-based) of `TEXT`.

**Parameters**

- `TEXT`: the Markdown source.
- `TOP`: the 0-based source line. The state is the one before that line.
- `VAR`: the name of the variable that receives the state.

**Notes**

- The state is the `FENCE` argument of [`tui.md.style_lines`](/api/markdown/tui.md.style_lines.html).

**Example**

```bash
tui.md.fence_before "$(<notes.md)" 40 fence
```

**See also:** [`tui.md.style_lines`](/api/markdown/tui.md.style_lines.html)
