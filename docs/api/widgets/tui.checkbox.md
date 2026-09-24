### `tui.checkbox`

```bash
tui.checkbox ID PANE ROW LABEL [CHECKED] [ACTION]
```

Creates a checkbox.

**Parameters**

- `CHECKED`: `1`, `true` or `yes` to start checked. Anything else starts unchecked.
- `ACTION`: function called as `ACTION ID VALUE` after each toggle: the checkbox id, then the new value `0` or `1`.

**Returns:** `1` when `ID` or `PANE` is empty.

**Notes**

- The id comes first, as for every widget callback, so one function can handle a whole group of checkboxes.
- [`tui.get`](/api/widgets/tui.get.html) prints `0`/`1`; [`tui.get.checked`](/api/core/tui.get.checked.html) works in conditions.

**Example**

```bash
tui.checkbox chk_wrap  opts 0 "Wrap lines"   1 on_opt
tui.checkbox chk_times opts 1 "Show times"   0 on_opt
on_opt() {                           # ID VALUE
    case "$1" in
        chk_wrap)  tui.config.set my.wrap  "$2" ;;
        chk_times) tui.config.set my.times "$2" ;;
    esac
}
```

**See also:** [`tui.checkbox.toggle`](/api/widgets/tui.checkbox.toggle.html)
