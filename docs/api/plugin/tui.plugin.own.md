### `tui.plugin.own`

```bash
tui.plugin.own TYPE VALUE
```

Adds something to what disabling the current plugin undoes. Only has an effect while a plugin is being enabled.

**Parameters**

- `TYPE`: `cmd` (command id), `bind` (key spec, plus `--pane ID`), `hook` (`EVENT FN`), `every` (timer id), `tick` (function), `overlay` (draw function), `provider` (function), or `run` (shell code that is `eval`ed on disable).

**Notes**

- Registrations made through the regular `tui.*` calls are recorded automatically; use this for things they don't cover.

**Example**

```bash
plugin.myplug.on_enable() {
    stty -ixon
    tui.plugin.own run "stty ixon"
}
```
