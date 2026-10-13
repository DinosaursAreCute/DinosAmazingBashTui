### `tui.get.raw_input`

```bash
tui.get.raw_input
```

Prints the bytes the terminal sent for the last key or mouse press, with control characters in caret notation: `^[` is ESC, `^?` is DEL, `^A` is ctrl+a. Pointer motion is not recorded.

**Notes**

- Meant for debugging key names: `^[[55;4u` is `alt+shift+7` as a kitty-style sequence, `^[7` is `alt+7`. The Debug > Feature lab shows it under "last input".
- The paste, focus and resize events are not recorded.

**Example**

```bash
tui.capture raw tui.get.raw_input
```
