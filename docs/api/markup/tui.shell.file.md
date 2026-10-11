### `tui.shell.file`

```bash
tui.shell.file [VAR]
```

Gives the canonical path of the shell the current page is built on: stored in `VAR` (no subshell), or printed when `VAR` is omitted. Nothing is printed for a page without a shell.

**Returns:** `0` when the page has a shell, `1` when it has none.

**Notes**

- A page names its shell with `<tui shell="_shell.xml">`; see "Shells" in the markup guide.
- Use it in callbacks that must behave differently inside a shell, for example to decide whether chrome widgets exist.

**Example**

```bash
on_visit() {
	local shell
	tui.shell.file shell
	[[ -n "$shell" ]] && tui.set_label crumb "inside the shell"
}
```
