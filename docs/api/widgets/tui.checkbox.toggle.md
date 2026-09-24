### `tui.checkbox.toggle`

```bash
tui.checkbox.toggle ID
```

Flips a checkbox, redraws it and calls its action as `ACTION ID VALUE`, as a click would.

**Notes**

- Does nothing for a widget that is not a checkbox.
- To set a value without calling the action, use [`tui.update`](/api/widgets/tui.update.html) `ID 0|1`.
