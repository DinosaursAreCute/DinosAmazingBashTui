# Animation and background painting

Three tools, from cheapest to most independent. Pick the first one that holds your frame rate.

| Tool | Runs in | Use for |
|---|---|---|
| `tui.every` + `tui.set_text` | the main loop | a clock, a counter, a progress bar |
| `tui.every` + `tui.set_canvas` | the main loop | a few cells of coloured animation (20 fps and up) |
| `tui.async.*` | a process of its own | full-pane animation that must never delay a key press or a hover |

## 1. Timers: `tui.every`

```bash
tui.every 40 spin_step       # every 40 ms
```

The shortest interval is 20 ms. While a job asks for less than 50 ms, `tui.run` waits only until the next job is due, so frames come at the rate asked for; an app without such a job keeps the idle-friendly poll and uses no CPU while nothing happens. Pause and resume with `tui.every.pause` and `tui.every.resume`, remove with `tui.every.cancel`.

A tick that takes longer than its interval delays input. Keep a tick under a few milliseconds, or move the drawing to a painter (section 3).

## 2. Ready-made frames: `tui.set_canvas`

`tui.set_text` measures and cuts the text and debounces the repaint. For animation, build the rows yourself and hand them over:

```bash
tui.set_canvas rain "$frame"     # rows already as wide as the pane, ANSI allowed
```

Nothing is measured, the pane draws at once, and a frame made for another size is not drawn until you make a new one (so a resize never shows a wide frame in a narrow pane). Read the pane's size with `tui.pane_size`, and rebuild the frame on the next tick.

## 3. Painters: `tui.async.*`

A painter is a function that runs in its own process and writes straight to the terminal with absolute cursor moves. Its frames cost the main loop nothing, so hover and focus highlighting stay instant.

```bash
rain() {
	while kill -0 "$_TUI_ASYNC_PARENT" 2>/dev/null; do
		printf '\e[%d;%dH%s' "$row" "$col" "$cell"
		tui.async.wait 0.05          # sleeps on a FIFO, no fork
	done
}
tui.async.start rain rain
tui.async.put rain speed 3           # main loop -> painter
```

- `tui.async.put NAME KEY VALUE` and `tui.async.get NAME KEY [VAR]` pass small values by state file, in either direction.
- `tui.async.covered` is true while a modal, a layer or the command palette is open, or while a resize is applied. A painter checks it and skips drawing so it never paints through an overlay. The runtime also holds painters while it applies a resize.
- Painters end with `tui.async.stop NAME`, `tui.async.stop_all`, on `tui.reset_ui` (page change outside a shell) and on exit.
- Keep a frame small and write it with one `printf` so a main-loop write rarely lands in the middle of it.

The Home demo page (`share/demo/home.xml`, `home_callbacks.sh`) is the worked example: a banner that types itself out, matrix rain as a painter that respects a mask of the cells owned by other panes, and a rotating line of news. `TUI_HOME_RAIN=0` switches the rain off.

## 4. Why overlays do not flicker

A repaint of the page under an open layer, dialog or command palette carries that overlay in the same synchronized write (`_tui._flush`), so a timer tick or a painter frame behind a window never shows through, and moving a window does not erase the screen.

See also: [Fast apps](performance.md), [Layers](markup.md) (guide section "Layers"), the API entries for [`tui.every`](/api/core/tui.every.html), [`tui.set_canvas`](/api/core/tui.set_canvas.html) and [`tui.async.start`](/api/core/tui.async.start.html).
