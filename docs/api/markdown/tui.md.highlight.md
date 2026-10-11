### `tui.md.highlight`

```bash
tui.md.highlight LANG FN
```

Registers the highlighter of a code fence language.

**Parameters**

- `LANG`: the fence language, matched case-insensitively.
- `FN`: the function, called as `FN LINE`. It sets `TUI_MD_HL` to `LINE` with SGR spans; the characters are unchanged. An empty `FN` unregisters the language.

**Notes**

- Built in: `bash` (also `sh`, `shell`, `zsh`) and `json`, using the classes `hl_keyword`, `hl_string`, `hl_comment`, `hl_number` and `hl_var`.

**Example**

```bash
tui.md.highlight ini my_ini_highlight
```
