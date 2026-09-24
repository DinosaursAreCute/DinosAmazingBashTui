### `tui.modal.open`

```bash
tui.modal.open NAME KEYFN DRAWFN [MOUSEFN]
```

Opens a modal: an overlay that receives all input until it is closed.

**Parameters**

- `NAME`: modal name, for [`tui.modal.active`](/api/chrome/tui.modal.active.html).
- `KEYFN`: called as `KEYFN KEY` for every key (`a`, `enter`, `ctrl+p`, ...), and `KEYFN paste` with `TUI_EVENT_PASTE` set.
- `DRAWFN`: draws the modal.
- `MOUSEFN`: called as `MOUSEFN EVENT X Y` (`mouse:left`, `wheel:up`, ... at a 1-based cell). Without it, mouse events are ignored.

**Notes**

- Opening a modal closes the one already open. Dialogs and the palette are modals too.
- While open, bindings, focus and scrolling are suspended. Only the terminal-mode chord still works.
- Closed on page change.
- Call [`tui.modal.redraw`](/api/chrome/tui.modal.redraw.html) after your state changes.

**Example**

```bash
my_draw() { tui.overlay.box 5 10 40 "1;97;44" "Confirm" "Delete file?" "[y] yes   [n] no"; }
my_keys() { case "$1" in y) do_delete; tui.modal.close ;; n|esc) tui.modal.close ;; esac; }
tui.modal.open confirm my_keys my_draw
```
