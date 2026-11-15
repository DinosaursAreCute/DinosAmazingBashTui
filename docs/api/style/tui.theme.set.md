### `tui.theme.set`

```bash
tui.theme.set FILE
```

Sets an app-wide stylesheet that is layered over every page's own theme, and reloads the current page.

**Notes**

- Lasts for this run only. To keep it across restarts, also `tui.config.set theme FILE` (the Settings page does both).
- The reload runs the page's `on_visit` again.
- `FILE` may start with `dabt:` for a file of DABT's defaults folder: `tui.theme.set "dabt:themes/nord.css"`.
- Returns 1 and keeps the current theme when `FILE` cannot be read. The log names the caller (`tui.theme.set at run.sh:21`) and suggests a nearby or `dabt:` file when it finds one.

**Example**

```bash
tui.theme.set "$APP/themes/ocean.css"
```

**See also:** [`tui.theme.clear`](/api/style/tui.theme.clear.html)
