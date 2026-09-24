### `tui.passthrough`

```bash
tui.passthrough [on|off|toggle]
```

Terminal mode: hands mouse and keyboard back to the terminal so its native selection, copy, link clicking and scrolling work. Default: `toggle`.

**Notes**

- The screen is frozen while on: no timers, repaints or resize layouts. Background jobs keep running and their output appears when you leave.
- Every key except the toggle chord (`ctrl+alt+p` by default) is ignored.
- Independent of the keyboard kill switch.

**See also:** [`tui.passthrough.key`](/api/input/tui.passthrough.key.html)
