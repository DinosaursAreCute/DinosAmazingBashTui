### `tui.mouse.capture`

```bash
tui.mouse.capture ID FN
```

Routes the held mouse button to `FN` until it is released, wherever the pointer moves. Call it from a press handler. `FN EVENT ID X Y` runs for every drag (`EVENT` is `drag`) and once on release (`EVENT` is `release`); `X Y` is the absolute 1-based cell. `FN` decides what the gesture means.

**Parameters**

- `ID`: passed back to `FN` (a widget or pane id).
- `FN`: the handler, called as `FN drag|release ID X Y`.

**Notes**

- A new press ends a capture whose release was lost (button let go outside the terminal).
- Built in: a scrollbar thumb keeps following the pointer off the bar; a button runs its action on release, and only if the pointer is still over it.

**See also:** [`tui.action.click`](/api/input/tui.action.click.html)
