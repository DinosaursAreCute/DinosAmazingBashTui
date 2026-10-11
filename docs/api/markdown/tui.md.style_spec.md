### `tui.md.style_spec`

```bash
tui.md.style_spec CLASS SPEC
```

Restyles one Markdown style class from `SPEC`, given as `FG[/BG][:MOD,MOD...]`.

**Parameters**

- `CLASS`: one of `h1` to `h6`, `strong`, `em`, `code`, `codeblock`, `quote`, `bullet`, `link`, `hr`, `marker`, `strike`, `hl_keyword`, `hl_string`, `hl_comment`, `hl_number`, `hl_var`, `page`, `table` (the outline of tables) or `table_head` (the header row). `page` is the document background: every rendered row is padded to the width under it. It is empty by default.
- `SPEC`: `FG` optionally followed by `/BG`, then optionally `:` and comma-separated modifiers. `FG` and `BG` are `default` (`BG` only), a name from `TUI_MD_COLORS` (`black red green yellow blue magenta cyan white gray bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white`) or `#rrggbb`. Modifiers are from `TUI_MD_MODS` (`bold dim italic underline reverse strike`). An empty `SPEC` restores the default style of `CLASS`.

**Returns:** `1` and changes nothing for an unknown class, color or modifier.

**Notes**

- The spec is remembered, so [`tui.md.style_spec_of`](/api/markdown/tui.md.style_spec_of.html) reports it back.
- [`tui.md.style_reset`](/api/markdown/tui.md.style_reset.html) undoes the change.
- A spec set here goes on top of the base look chosen with [`tui.md.profile`](/api/markdown/tui.md.profile.html).

**Example**

```bash
tui.md.style_spec h1 "cyan:bold,underline"
tui.md.style_spec code "#ff8000"
tui.md.style_spec page "white/#102030:bold"
```
