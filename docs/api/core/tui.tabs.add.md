### `tui.tabs.add`

```bash
tui.tabs.add TAB_ID TEXT ACTION [DEFAULT]
```

Registers one tab before the group is built.

**Parameters**

- `TAB_ID`: widget id of the tab's header button.
- `TEXT`: header caption.
- `ACTION`: function called as `ACTION TAB_ID` whenever the tab is activated. It fills the content pane.
- `DEFAULT`: `true` to activate this tab when the group is built. Any other value counts as not default.

**See also:** [`tui.tabs.build`](/api/core/tui.tabs.build.html)
