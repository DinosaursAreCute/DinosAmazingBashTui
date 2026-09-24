### `tui.class`

```bash
tui.class ID CLASS
```

Applies a theme class to a widget or pane: its normal rules and every pseudo-state it defines (`:focus`, `:border`, `:title`, `:hover`, `:checked`, `:unchecked`).

**Parameters**

- `CLASS`: class name without the dot. Empty does nothing.

**Notes**

- Copies the class's current values. Changing or reloading the theme afterwards does not restyle `ID`; reloading the page does.
- Several calls layer: a later class overrides only the fields it sets.
- `class="…"` in markup calls this.

**Example**

```bash
tui.class btn_go nav_link
```
