### `tui.debug.devtools`

```bash
tui.debug.devtools [open|close|toggle|focus|blur]
```

Opens or closes the dev-tools dock above the debug strip, or moves the keyboard to or from it; `dabt --debug` binds F11 to it.

**Notes**

- Tabs: Events (live event log), Pages (page cache and loads), Perf (span timings), Counters (perf counters and event totals).
- The dock takes about 30% of the terminal (at least 8 rows) from the page; `m` maximises it.
- While it has focus: `←→` or `1`-`4` switch tab, `↑↓ pgup pgdn home end` scroll, `p` pauses the Events tab, `f` cycles the category filter, `c` clears events, `esc` gives the keyboard back to the app and leaves the dock open.
- Those keys are bound on focus and unbound on blur, so the app's own keys work again once the dock is blurred.
