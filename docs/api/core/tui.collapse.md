### `tui.collapse`

```bash
tui.collapse PANE [toggle|on|off]
```

Collapses (`on`), expands (`off`) or toggles (default) a collapsible pane, then lays out again.

**Parameters**

- `PANE` - pane id. Must have `collapsible="true"` (or be a `<details>`) in an `h` or `v` split.
- `MODE` - enum (toggle|on|off), optional, default toggle.

**Returns:** `1` when `PANE` is not collapsible, the mode is unknown or nothing changed.

**Notes**

- A collapsed pane shrinks along its parent's split axis to `collapse_to` (`title`, `0` or `rail`); the freed space goes to the siblings with an `fr` weight and expanding restores the previous size spec. The widgets of a collapsed pane are hidden: not drawn, focusable or hit-testable, and focus inside the pane moves to the next focusable widget. A rail shows each button's `collapsed_text` instead.
- In an exclusive `<accordion>` expanding a pane collapses its siblings. `on_toggle` callbacks (`FN PANE STATE`, `STATE` is `collapsed` or `expanded`) run for every pane that changed, `on_resize` callbacks for every pane that changed size.
- A collapsible pane has a collapse button: a 2-cell control drawn on its border at the corner of the edge that moves. In an `h` split that is the top of the right edge (the left edge for the last pane), in a `v` split the left end of the bottom edge (the top edge for the last pane). The arrow points where the edge moves (`◀` for an expanded first pane, `▶` for an expanded last pane, `▲` / `▼` in a `v` split) and flips while collapsed. It stays visible on a `rail` or `title` bar; `collapse_to="0"` has none. A click on it calls this with `toggle`; `alt+c` (`tui.action.collapse_toggle`) does it from the keyboard.
- Theme classes: `.collapse_button` (base), `.collapse_button:hover` (the pointer is over it) and `.collapse_button:collapsed` (the pane is collapsed; hover wins over it, field by field). A pane picks another class with `collapse_class="NAME"` (`NAME`, `NAME:hover`, `NAME:collapsed`; the validator warns when no theme defines it). Resizable borders use `.resize_handle:hover` the same way. Every bundled theme defines all of them.
- Keyboard: `alt+c` is shown in the footer as `alt+c Collapse` / `alt+c Expand` while the focus is inside a collapsible pane (it does not fire while a text input has focus: the input owns it). `collapse_key="KEY"` (any key name of the bind table, e.g. `ctrl+1`, `f5`) binds a direct toggle for that pane that works from anywhere on the page, also from a text input; the bind is dropped with the page. The validator reports an unknown key name and a key used twice on the page (also against a `<bind key>`) as errors.

**See also:** [`tui.collapsed`](/api/core/tui.collapsed.html), [`tui.resize`](/api/core/tui.resize.html)
