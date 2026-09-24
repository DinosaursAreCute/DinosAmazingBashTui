### `tui.bind`

```bash
tui.bind KEY COMMAND [--pane ID] [--pass] [--always] [--page] [--user] [--desc TEXT]
```

Binds a key or mouse event to a command.

**Parameters**

- `KEY`: a key name such as `a`, `Q`, `ctrl+s`, `alt+enter`, `shift+tab`, `f5`, `pgdn`, or a mouse name such as `mouse:right`, `wheel:down`, `drag:left`. Names are case-insensitive except single letters (`Q` is `shift+q`).
- `COMMAND`: a function name with optional arguments, e.g. `"tui.action.scroll down 10"`. Several commands can be chained with `;`.

**Options**

- `--pane ID`: only when `ID` is the event's pane: the focused widget's pane for keys, the pane under the pointer for mouse events.
- `--pass`: after this command, keep going down the lookup order, so the default still runs too.
- `--always`: also fire while a text widget has focus and would otherwise take the key.
- `--page`: removed on the next page change. `<bind>` in markup uses this.
- `--user`: a binding made by the person using the app. It beats code bindings and is saved with [`tui.bind.save`](/api/input/tui.bind.save.html).
- `--desc TEXT`: description shown in binding lists and the Keybinds page.

**Returns:** `1` when `KEY` or `COMMAND` is missing.

**Notes**

- Lookup order per event: pane-scoped user, pane-scoped code, global user, global code, then the built-in default. The first match stops the search unless it was bound with `--pass`.
- `COMMAND` is split on `;` and spaces, not evaluated: arguments can't contain spaces or quotes. Wrap anything more complex in a function.
- A command that is not defined when the key is pressed is skipped; the reason is left in `TUI_LAST_BIND_ERROR`.
- Binding the same `KEY` (and pane) again replaces the command and its flags.
- Unknown flags are ignored.
- Bindings made while a plugin loads are removed when that plugin is disabled.

**Example**

```bash
tui.bind ctrl+e on_export --desc "Export"
tui.bind mouse:right on_ctx --pane output
tui.bind ctrl+s on_save --always
tui.bind q "log_quit; tui.action.quit"
```

**See also:** [`tui.unbind`](/api/input/tui.unbind.html), [`tui.defaults.off`](/api/input/tui.defaults.off.html), [../guide/input-bindings.md](/guide/input-bindings.html)
