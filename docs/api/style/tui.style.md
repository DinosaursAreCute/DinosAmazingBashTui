### `tui.style`

```bash
tui.style ID FG BG MODS [STATE]
```

Sets the style of a widget or pane directly, without a theme class.

**Parameters**

- `FG`, `BG`: `black red green yellow blue magenta cyan white default`, the bright variants `br_black` ... `br_white`, or `#rrggbb`. `""` leaves the field unchanged.
- `MODS`: space-separated, from `bold dim italic underline blink reverse hidden strike`. `""` leaves it unchanged.
- `STATE`: `normal` (default), `focus`, `border`, `title`, `hover`, `checked`, `unchecked`.

**Notes**

- A field can't be cleared once set; set it to another value instead.

**Example**

```bash
tui.style status "" "#1e1e2e" bold
tui.style status yellow "" "" border
```
