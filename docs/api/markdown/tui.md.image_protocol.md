### `tui.md.image_protocol`

```bash
tui.md.image_protocol VAR
```

Stores in `VAR` the image protocol of the terminal: `kitty`, `iterm2` or `none`.

**Parameters**

- `VAR`: the name of the variable that receives the protocol.

**Notes**

- `kitty` is reported for kitty and Ghostty (the protocol with Unicode placeholders that `tui.md.images graphics` draws), `iterm2` for iTerm2 and WezTerm (another protocol, not drawn), `none` otherwise and also inside tmux, which needs passthrough.
- Detection reads `TUI_MD_IMAGE_PROTOCOL` (an override: `kitty`, `iterm2`, `none`), then `TMUX`, `KITTY_WINDOW_ID`, `TERM`, `TERM_PROGRAM`, `GHOSTTY_RESOURCES_DIR` and `LC_TERMINAL`.
- Only `kitty` is drawn by DABT; the iTerm2 protocol is detected but pictures stay placeholders there.

**Example**

```bash
tui.md.image_protocol proto    # proto=kitty in kitty
```
