### `tui.config.set`

```bash
tui.config.set KEY VALUE
```

Stores a setting and writes the config file immediately.

**Parameters**

- `KEY`: setting name. Any key is accepted; see the module intro for the ones the framework reads.
- `VALUE`: the value. Must not contain a newline.

**Returns:** `1` when the config directory cannot be created, else `0`.

**Notes**

- Does not apply the change to the running app. Framework keys read at start (`theme`, `defaults.off`, `input.*`, `notify.*`) take effect on the next start or after [`tui.config.apply`](/api/config/tui.config.apply.html); `confirm.quit` is read at quit time and takes effect at once.
- Rewrites the whole file on every call. Don't call it from a timer or tick function.

**Example**

```bash
tui.config.set confirm.quit 1
```

**See also:** [`tui.config.get`](/api/config/tui.config.get.html), [`tui.config.unset`](/api/config/tui.config.unset.html)
