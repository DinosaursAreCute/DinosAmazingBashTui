### `tui.modal.count_keys`

```bash
tui.modal.count_keys "KEY ..."
```

Names the keys the open modal's key function handles with a repeat count, so a held key reaches it as one call instead of one per press.

**Parameters**

- `"KEY ..."` - canonical key names separated by spaces, e.g. `"up down pgup pgdn"`.

**Notes**

- Call it right after [`tui.modal.open`](tui.modal.open.md); it is cleared when the modal closes.
- When identical presses of a named key are already waiting in the input, they are merged into one event. The key function sees `TUI_EVENT_COUNT` set to the number of presses and moves by that many, with one redraw.
- Only name keys that move or scroll. Typing and one-shot keys (`enter`, `esc`) should not be counted.

**Example**

```bash
tui.modal.open pick my_keys my_draw
tui.modal.count_keys "up down"
my_keys() { [[ $1 == down ]] && ((sel += TUI_EVENT_COUNT)); tui.modal.redraw; }
```
