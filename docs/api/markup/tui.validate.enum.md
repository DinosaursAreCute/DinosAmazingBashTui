### `tui.validate.enum`

```bash
tui.validate.enum TAG|* ATTR "a|b|c"
```

Restricts an attribute to a list of values. `*` applies it to every tag.

**Example**

```bash
tui.validate.enum pane border "none|single|double|heavy"
```
