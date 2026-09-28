### `tui.parse.file`

```bash
tui.parse.file FILE
```

Tokenizes `FILE` (and every `<include src="…">` it pulls in) into the node store (`lib/markup/tui_node.sh`): resets the node store, then parses. Sets `_P_ROOT` to the synthetic "document" node whose children are the file's top-level tags. Parse errors are appended to `_P_ERRORS`, not printed.

**Notes**

- Fork-free: the file is read once with `read -d ''`, then walked by string index - no per-line `read`, no per-attribute regex pass over a raw line.
- A tag may span multiple physical lines and use either quote style; a comment can appear anywhere.
- `<include src="…">` is expanded inline: the included file's top-level tags become children of the current parent, in place - no "include" node is ever created. A cycle is reported in `_P_ERRORS` and skipped.
- Building the tree into panes/widgets is a separate step (`tui_build.load`, `lib/markup/tui_build.sh`).

**Example**

```bash
tui.parse.file "$page"
tui_node.children "$_P_ROOT"
```
