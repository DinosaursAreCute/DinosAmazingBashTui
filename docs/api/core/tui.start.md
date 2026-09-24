### `tui.start`

```bash
tui.start FILE
```

Runs a markup-driven app: validates the page, initializes the terminal, loads `FILE` and runs the main loop until the app quits.

**Parameters**

- `FILE`: the first page (XML).

**Returns:** `1` when `FILE` is unreadable, fails validation or fails to load; otherwise returns after the app quits.

**Notes**

- Validates `FILE` and its includes before the terminal is taken over. Errors are printed to stderr and abort the start, unless `TUI_IGNORE_INVALID_XML=1` (set by `dabt --ignore-invalid-xml`). `TUI_VALIDATE=0` skips validation.
- Sets `TUI_THEMES_DIR` to the page's `themes/` folder (else the defaults' `themes/`) when it is not already set.
- The terminal is restored on every exit path: normal quit, `INT`/`TERM`, or a load failure.
- Uses the page cache for later `tui.goto` calls but does not pre-warm it; see [`tui.start_cached`](/api/core/tui.start_cached.html).

**Example**

```bash
#!/usr/bin/env bash
TUI_APP_NAME=my_app                 # before sourcing: names the config folder and log file
source /path/to/lib/tui.sh
tui.start "$APP/config/home.xml"
```

**See also:** [`tui.start_cached`](/api/core/tui.start_cached.html), [`tui.init`](/api/core/tui.init.html), [`tui.run`](/api/core/tui.run.html)
