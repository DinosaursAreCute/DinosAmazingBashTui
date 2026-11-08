### `tui.variant`

```bash
tui.variant ID [NAME]
```

Picks the design a widget draws with, so several progress bars, checkboxes, selects or lists can look different side by side. Markup: `variant="NAME"`.

**Parameters**

- `ID` - a progress bar, checkbox, select, list, table or textarea, or a scrolling pane (its scrollbars).
- `NAME` - a design from the theme. An empty or missing `NAME` goes back to the base look.

**Notes**

- A variant is a `.type.NAME` rule: `.progress.thin { fill: "━"; empty: "━"; }`. Slots it leaves out come from the base `.type` rule, then the built-in default. A name the active theme does not define draws the base look, so switching themes never breaks a page.
- A progress bar's colours follow the same rule: `.progress.NAME` and `.progress_fill.NAME` override the base fields they set.
- Built-in designs (`share/defaults/glyphs/variants.css`): progress `thin dots squares ascii`, checkbox `round plain`, select `plain angle`, scroll indicators of lists, tables and textareas `thin block dot`, scrollbars of scrolling panes `block dot line`.

**Example**

```bash
tui.variant eta_bar thin
```
