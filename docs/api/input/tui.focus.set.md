### `tui.focus.set`

```bash
tui.focus.set ID ATTR VALUE
```

Sets one focus attribute of a widget. Every attribute is also a markup attribute on every widget tag, so most pages never call this.

**Parameters**

| `ATTR` | Values | Default | Effect |
|---|---|---|---|
| `focusable` | `true`, `false` | by widget type | Whether the widget can hold keyboard focus. Buttons, inputs, checkboxes, passwords, textareas, lists, tables and selects can; labels and progress bars cannot. |
| `tabbable` | `true`, `false` | same as `focusable` | Whether Tab stops on it. A non-tabbable widget can still be focused by click or by `focus_next`/`focus_prev`. |
| `tab_order` | integer ≥ 1, `0`, `-1` | unset | `0` is visited first, then `1`, `2`, … ascending, then widgets without a value in document order, then `-1` last. Ties keep document order. |
| `focus_group` | name | none | Widgets with the same name form a group (see `focus_nav`). |
| `focus_nav` | `tab`, `arrows`, `both` | `tab` | `arrows`: the group is one Tab stop (Tab re-enters at the member focused last) and the arrow keys move inside it. `both`: arrows move inside the group and Tab also visits every member. Read from any member of the group. |
| `focus_wrap` | `true`, `false` | `true` | Whether the arrow keys wrap at the ends of the group. Read from any member. |
| `focus_next`, `focus_prev` | widget id | none | The widget Tab / Shift+Tab jumps to from this one, instead of the next in order. |
| `autofocus` | `true` | unset | Focuses the first such widget (in Tab order) when the page is first drawn, unless something already has focus. |

**Returns:** `1` for an unknown `ATTR`, or for a `focusable`/`tabbable` value other than `true`/`false`.

**Notes**

- Tab stop: one position in the Tab sequence. Usually one widget; a `focus_nav="arrows"` group counts as one.
- The validator reports a `tab_order` that skips a number or is used twice (warnings), and `tabbable` on a widget that cannot be focused (error).
- `<tui focus_wrap="false">` stops Tab at the first and last stop instead of wrapping.

**Example**

```xml
<button id="ok" pane="form" row="1" tab_order="1" autofocus="true" text="OK"/>
<button id="cancel" pane="form" row="2" tab_order="2" text="Cancel"/>
<button id="help" pane="form" row="3" tab_order="-1" text="Help"/>
<button id="opt_a" pane="form" row="4" focus_group="mode" focus_nav="arrows" text="Fast"/>
<button id="opt_b" pane="form" row="5" focus_group="mode" focus_nav="arrows" text="Safe"/>
```

```bash
tui.focus.set help tabbable false # same as tabbable="false" in markup
```

**See also:** [`tui.focus`](/api/widgets/tui.focus.html), [`tui.action.focus_next`](/api/input/tui.action.focus_next.html), [`tui.hit.set`](/api/input/tui.hit.set.html)
