### `tui.md.style_lines`

```bash
tui.md.style_lines FENCE LINE...
```

Styles consecutive source lines for an editor overlay: one row per `LINE`, characters unchanged, delimiters in the marker class.

**Parameters**

- `FENCE`: the code-fence state in force before the first line: `""` outside a fence, `CHAR:LEN` inside one (as stored by [`tui.md.fence_before`](/api/markdown/tui.md.fence_before.html)).
- `LINE...`: the source lines, in order.

**Results**

- `TUI_MD_ROWS`: array with one styled row per `LINE`.

**Notes**

- Rows of lines outside fences are memoized. The memo is dropped when [`tui.md.style_set`](/api/markdown/tui.md.style_set.html) or [`tui.md.mono`](/api/markdown/tui.md.mono.html) change the style table.

**Example**

```bash
tui.md.fence_before "$(<notes.md)" 40 fence
tui.md.style_lines "$fence" "${visible[@]}"
```

**See also:** [`tui.md.style`](/api/markdown/tui.md.style.html), [`tui.md.fence_before`](/api/markdown/tui.md.fence_before.html)
