### `tui.tabs.build`

```bash
tui.tabs.build TABS_ID HEADER_PANE CONTENT_PANE TAB_ID...
```

Builds the header row for registered tabs and activates the default tab (or the first).

**Parameters**

- `TABS_ID`: a name for the group.
- `HEADER_PANE`: leaf pane that receives a one-row grid of header buttons.
- `CONTENT_PANE`: the pane the tab actions fill.
- `TAB_ID...`: tabs registered with [`tui.tabs.add`](/api/core/tui.tabs.add.html), in display order.

**Notes**

- Header cells are named `HEADER_PANE_TAB_ID_cell` and skip the content-fit check, so long captions clip instead of showing the size notice.
- The active tab is shown with the header button's focus style.
- The framework does not clear `CONTENT_PANE` between tabs; each action replaces what it needs.

**Example**

```bash
tui.tabs.add tab_log  "Log"   show_log true
tui.tabs.add tab_conf "Config" show_conf
tui.tabs.compact main_tabs
tui.tabs.build main_tabs tab_bar tab_body tab_log tab_conf
```

**See also:** [`tui.tabs.activate`](/api/core/tui.tabs.activate.html)
