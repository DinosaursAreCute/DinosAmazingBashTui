### `tui.md.profile`

```bash
tui.md.profile dabt|theme
```

Chooses the base look of the Markdown styles: DABT's own style table, or the active theme's `.md_CLASS` rules.

**Parameters**

- `dabt|theme`: `dabt` is DABT's own style table; `theme` takes the `.md_CLASS` rules of the active theme (`fg`, `bg` and `mods`, as for any theme class) and keeps DABT's look for the classes the theme does not define.

**Returns:** `1` for another name.

**Notes**

- The classes are `h1` to `h6`, `strong`, `em`, `code`, `codeblock`, `quote`, `bullet`, `link`, `hr`, `marker`, `strike`, `hl_keyword`, `hl_string`, `hl_comment`, `hl_number`, `hl_var`, `page`, `table` (the outline of tables) and `table_head` (the header row).
- Styles set with [`tui.md.style_spec`](/api/markdown/tui.md.style_spec.html) always go on top of the profile.
- Persisted as `md.profile` in the config (see [`tui.md.config_apply`](/api/markdown/tui.md.config_apply.html)).

**Example**

```bash
tui.md.profile theme
```
