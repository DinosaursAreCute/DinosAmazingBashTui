### `tui.clipboard.copy`

```bash
tui.clipboard.copy TEXT
```

Copies `TEXT` to the system clipboard through the terminal (OSC 52).

**Notes**

- Works in kitty, foot, WezTerm, Alacritty, iTerm2 and tmux (with `set-clipboard on`). GNOME Terminal and other VTE terminals ignore it silently.
- Some terminals cap the size of an OSC 52 payload.
